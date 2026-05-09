import express from 'express';
import mongoose from 'mongoose';
import { createServer } from 'http';
import { Server } from 'socket.io';
import cors from 'cors';
import cookieParser from 'cookie-parser';
import dotenv from 'dotenv';

// Import tracing utilities
import { 
  TracingUtils, 
  traceMongoDB, 
  traceWebSocket, 
  expressTracingMiddleware, 
  errorTracingMiddleware 
} from './tracer.js';

// Import existing routes and middleware
import { authMiddleware } from '../middleware/auth.js';
import userRoutes from '../routes/user.routes.js';
import messageRoutes from '../routes/message.routes.js';
import chatRoutes from '../routes/chat.routes.js';

dotenv.config();

class InstrumentedChatApp {
  constructor() {
    this.app = express();
    this.server = createServer(this.app);
    this.io = new Server(this.server, {
      cors: {
        origin: process.env.FRONTEND_URL || "http://localhost:3000",
        methods: ["GET", "POST"]
      }
    });
    
    this.initializeDatabase();
    this.initializeMiddleware();
    this.initializeRoutes();
    this.initializeWebSocket();
    this.initializeErrorHandling();
  }

  async initializeDatabase() {
    try {
      await TracingUtils.traceAsyncOperation(
        'database.connection',
        async (span) => {
          span.setAttribute('db.system', 'mongodb');
          span.setAttribute('db.connection_string', process.env.MONGODB_URI);
          
          await mongoose.connect(process.env.MONGODB_URI);
          
          span.setAttribute('db.status', 'connected');
          span.addEvent('database.connected', {
            timestamp: Date.now(),
          });
        }
      );
      
      // Enable MongoDB tracing
      traceMongoDB(mongoose);
      
      console.log('Connected to MongoDB with tracing enabled');
    } catch (error) {
      console.error('Database connection failed:', error);
      throw error;
    }
  }

  initializeMiddleware() {
    this.app.use(cors({
      origin: process.env.FRONTEND_URL || "http://localhost:3000",
      credentials: true
    }));
    
    this.app.use(cookieParser());
    this.app.use(express.json());
    
    // Add tracing middleware
    this.app.use(expressTracingMiddleware);
    this.app.use(authMiddleware);
  }

  initializeRoutes() {
    // Instrument user routes
    this.app.use('/api/users', this.instrumentRoute(userRoutes, 'users'));
    
    // Instrument message routes
    this.app.use('/api/messages', this.instrumentRoute(messageRoutes, 'messages'));
    
    // Instrument chat routes
    this.app.use('/api/chat', this.instrumentRoute(chatRoutes, 'chat'));

    // Health check endpoint with tracing
    this.app.get('/health', async (req, res) => {
      await TracingUtils.traceAsyncOperation(
        'health.check',
        async (span) => {
          span.setAttribute('health.check.type', 'readiness');
          
          const dbStatus = mongoose.connection.readyState === 1 ? 'connected' : 'disconnected';
          span.setAttribute('database.status', dbStatus);
          
          res.json({
            status: 'healthy',
            timestamp: new Date().toISOString(),
            database: dbStatus,
            tracing: 'enabled'
          });
        }
      );
    });
  }

  instrumentRoute(router, routeName) {
    return (req, res, next) => {
      TracingUtils.setAttribute(trace.getActiveSpan(), 'route.name', routeName);
      router(req, res, next);
    };
  }

  initializeWebSocket() {
    this.io.use(traceWebSocket);

    this.io.on('connection', (socket) => {
      const span = TracingUtils.createSpan('websocket.connection');
      span.setAttribute('websocket.event', 'connection');
      span.setAttribute('socket.id', socket.id);
      span.setAttribute('user.id', socket.user?.id);

      // Join user to their personal room
      if (socket.user?.id) {
        socket.join(`user_${socket.user.id}`);
        TracingUtils.addEvent(span, 'websocket.joined_room', {
          room: `user_${socket.user.id}`,
        });
      }

      // Join chat room
      socket.on('join_chat', async (chatId) => {
        await TracingUtils.traceAsyncOperation(
          'websocket.join_chat',
          async (operationSpan) => {
            operationSpan.setAttribute('chat.id', chatId);
            operationSpan.setAttribute('user.id', socket.user?.id);
            
            socket.join(`chat_${chatId}`);
            
            TracingUtils.addEvent(operationSpan, 'websocket.joined_chat', {
              chatId,
              timestamp: Date.now(),
            });
          }
        );
      });

      // Handle messages with tracing
      socket.on('send_message', async (messageData) => {
        await TracingUtils.traceAsyncOperation(
          'websocket.send_message',
          async (messageSpan) => {
            messageSpan.setAttribute('message.type', messageData.type);
            messageSpan.setAttribute('message.size', JSON.stringify(messageData.content).length);
            messageSpan.setAttribute('chat.id', messageData.chatId);
            messageSpan.setAttribute('user.id', socket.user?.id);
            
            try {
              // Save message to database with tracing
              const savedMessage = await TracingUtils.traceMongoOperation(
                'insert',
                'messages',
                { chatId: messageData.chatId, userId: socket.user?.id },
                async (mongoSpan) => {
                  const Message = mongoose.model('Message');
                  const message = new Message({
                    content: messageData.content,
                    chatId: messageData.chatId,
                    userId: socket.user?.id,
                    type: messageData.type || 'text'
                  });
                  
                  const result = await message.save();
                  mongoSpan.setAttribute('document.id', result._id);
                  return result;
                }
              );

              // Broadcast message with tracing
              this.io.to(`chat_${messageData.chatId}`).emit('receive_message', savedMessage);
              
              TracingUtils.addEvent(messageSpan, 'message.broadcasted', {
                recipients: 'chat_room',
                timestamp: Date.now(),
              });
              
            } catch (error) {
              messageSpan.recordException(error);
              throw error;
            }
          }
        );
      });

      socket.on('disconnect', (reason) => {
        TracingUtils.addEvent(span, 'websocket.disconnect', {
          reason,
          timestamp: Date.now(),
          duration: Date.now() - span.startTime,
        });
        span.end();
      });
    });
  }

  initializeErrorHandling() {
    // Global error handler with tracing
    this.app.use(errorTracingMiddleware);

    // 404 handler with tracing
    this.app.use((req, res) => {
      const span = TracingUtils.createSpan('404.error');
      span.setAttribute('http.url', req.url);
      span.setAttribute('http.method', req.method);
      span.setAttribute('http.status_code', 404);
      
      span.setStatus({
        code: 2, // ERROR
        message: 'Route not found',
      });
      
      res.status(404).json({ error: 'Route not found' });
      span.end();
    });
  }

  // Example of tracing external API calls
  async callExternalAPI(serviceName, endpoint, data) {
    return await TracingUtils.traceExternalCall(
      serviceName,
      'http_request',
      endpoint,
      async (span) => {
        span.setAttribute('http.method', 'POST');
        span.setAttribute('http.url', endpoint);
        
        // Example: Call Cloudinary API
        if (serviceName === 'cloudinary') {
          const response = await fetch(endpoint, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify(data)
          });
          
          span.setAttribute('http.status_code', response.status);
          span.setAttribute('external.service.response_time', response.headers.get('x-response-time'));
          
          return response.json();
        }
        
        throw new Error(`Unknown external service: ${serviceName}`);
      }
    );
  }

  start() {
    const port = process.env.PORT || 5000;
    
    this.server.listen(port, () => {
      console.log(`Server running on port ${port} with distributed tracing enabled`);
    });
  }
}

// Create and start the instrumented application
const app = new InstrumentedChatApp();
app.start();

export default app;
