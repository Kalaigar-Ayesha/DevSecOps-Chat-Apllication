import { NodeSDK } from '@opentelemetry/sdk-node';
import { Resource } from '@opentelemetry/resources';
import { SemanticResourceAttributes } from '@opentelemetry/semantic-conventions';
import { JaegerExporter } from '@opentelemetry/exporter-jaeger';
import { OTLPTraceExporter } from '@opentelemetry/exporter-otlp-grpc';
import { SimpleSpanProcessor, BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { getNodeAutoInstrumentations } from '@opentelemetry/auto-instrumentations-node';
import { ExpressInstrumentation } from '@opentelemetry/instrumentation-express';
import { MongoDBInstrumentation } from '@opentelemetry/instrumentation-mongodb';
import { HttpInstrumentation } from '@opentelemetry/instrumentation-http';
import { trace, SpanKind, SpanStatusCode } from '@opentelemetry/api';

// Initialize OpenTelemetry SDK
const initializeTracer = () => {
  const exporter = new JaegerExporter({
    endpoint: process.env.JAEGER_ENDPOINT || 'http://jaeger-collector:14250/api/traces',
    serviceName: process.env.SERVICE_NAME || 'chat-app-backend',
  });

  // Alternative: Use OTLP exporter for OpenTelemetry Collector
  const otlpExporter = new OTLPTraceExporter({
    url: process.env.OTEL_EXPORTER_OTLP_ENDPOINT || 'http://otel-collector:4317',
  });

  const sdk = new NodeSDK({
    resource: new Resource({
      [SemanticResourceAttributes.SERVICE_NAME]: process.env.SERVICE_NAME || 'chat-app-backend',
      [SemanticResourceAttributes.SERVICE_VERSION]: process.env.SERVICE_VERSION || '1.0.0',
      [SemanticResourceAttributes.DEPLOYMENT_ENVIRONMENT]: process.env.NODE_ENV || 'development',
      [SemanticResourceAttributes.HOST_NAME]: process.env.HOSTNAME || 'unknown',
    }),
    spanProcessor: new BatchSpanProcessor(exporter),
    instrumentations: [
      ...getNodeAutoInstrumentations(),
      new ExpressInstrumentation(),
      new MongoDBInstrumentation(),
      new HttpInstrumentation(),
    ],
  });

  sdk.start();
  console.log('OpenTelemetry tracing initialized');
};

// Custom tracing utilities
class TracingUtils {
  static tracer = trace.getTracer('chat-app-backend', '1.0.0');

  static createSpan(name, options = {}) {
    return this.tracer.startSpan(name, {
      kind: SpanKind.SERVER,
      ...options,
    });
  }

  static async traceAsyncOperation(name, operation, attributes = {}) {
    const span = this.createSpan(name);
    
    try {
      // Set attributes
      Object.entries(attributes).forEach(([key, value]) => {
        span.setAttribute(key, value);
      });

      const result = await operation(span);
      
      span.setStatus({ code: SpanStatusCode.OK });
      span.end();
      
      return result;
    } catch (error) {
      span.recordException(error);
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error.message,
      });
      span.end();
      throw error;
    }
  }

  static traceMongoOperation(operation, collection, query, operationFunc) {
    return this.traceAsyncOperation(
      `mongodb.${operation}`,
      (span) => {
        span.setAttribute('db.operation', operation);
        span.setAttribute('db.collection', collection);
        span.setAttribute('db.system', 'mongodb');
        
        if (query) {
          span.setAttribute('db.statement', JSON.stringify(query));
        }

        return operationFunc(span);
      }
    );
  }

  static traceHttpRequest(req, res, next) {
    const span = this.tracer.startSpan(req.path, {
      kind: SpanKind.SERVER,
      attributes: {
        'http.method': req.method,
        'http.url': req.url,
        'http.target': req.path,
        'http.host': req.headers.host,
        'user_agent': req.headers['user-agent'],
        'remote_addr': req.ip || req.connection.remoteAddress,
      },
    });

    // Add user context if available
    if (req.user && req.user.id) {
      span.setAttribute('user.id', req.user.id);
      span.setAttribute('user.email', req.user.email);
    }

    // Add request ID if available
    if (req.requestId) {
      span.setAttribute('request.id', req.requestId);
    }

    // Inject trace context for downstream calls
    const headers = {};
    this.tracer.inject(span, headers);
    Object.assign(req.headers, headers);

    res.on('finish', () => {
      span.setAttribute('http.status_code', res.statusCode);
      span.setAttribute('http.response_content_length', res.get('content-length') || 0);
      
      if (res.statusCode >= 400) {
        span.setStatus({
          code: SpanStatusCode.ERROR,
          message: `HTTP ${res.statusCode}`,
        });
      } else {
        span.setStatus({ code: SpanStatusCode.OK });
      }
      
      span.end();
    });

    res.on('error', (error) => {
      span.recordException(error);
      span.setStatus({
        code: SpanStatusCode.ERROR,
        message: error.message,
      });
      span.end();
    });

    next();
  }

  static traceExternalCall(serviceName, operation, url, operationFunc) {
    return this.traceAsyncOperation(
      `external.${serviceName}.${operation}`,
      (span) => {
        span.setAttribute('http.url', url);
        span.setAttribute('http.method', operation);
        span.setAttribute('peer.service', serviceName);
        span.setKind(SpanKind.CLIENT);

        return operationFunc(span);
      }
    );
  }

  static addEvent(span, eventName, attributes = {}) {
    span.addEvent(eventName, {
      timestamp: Date.now(),
      ...attributes,
    });
  }

  static setAttribute(span, key, value) {
    span.setAttribute(key, value);
  }
}

// MongoDB tracing middleware
const traceMongoDB = (mongoose) => {
  mongoose.connection.on('connected', () => {
    const span = TracingUtils.createSpan('mongodb.connection');
    span.setAttribute('db.system', 'mongodb');
    span.setAttribute('db.connection_string', mongoose.connection.host);
    span.end();
  });

  mongoose.connection.on('error', (error) => {
    const span = TracingUtils.createSpan('mongodb.error');
    span.recordException(error);
    span.setAttribute('db.system', 'mongodb');
    span.end();
  });
};

// WebSocket tracing utilities
const traceWebSocket = (socket, next) => {
  const span = TracingUtils.createSpan('websocket.connection', {
    attributes: {
      'websocket.event': 'connection',
      'user.id': socket.user?.id,
      'remote_addr': socket.handshake.address,
    },
  });

  socket.on('disconnect', (reason) => {
    TracingUtils.addEvent(span, 'websocket.disconnect', {
      reason,
      duration: Date.now() - span.startTime,
    });
    span.end();
  });

  socket.on('message', (data) => {
    TracingUtils.addEvent(span, 'websocket.message', {
      message_type: data.type,
      message_size: JSON.stringify(data).length,
    });
  });

  next();
};

// Express middleware for automatic tracing
const expressTracingMiddleware = (req, res, next) => {
  TracingUtils.traceHttpRequest(req, res, next);
};

// Error handling middleware
const errorTracingMiddleware = (error, req, res, next) => {
  const span = trace.getActiveSpan();
  if (span) {
    span.recordException(error);
    span.setStatus({
      code: SpanStatusCode.ERROR,
      message: error.message,
    });
    
    span.setAttribute('error.type', error.constructor.name);
    span.setAttribute('error.stack', error.stack);
    span.end();
  }

  next(error);
};

// Initialize tracing
initializeTracer();

export {
  TracingUtils,
  traceMongoDB,
  traceWebSocket,
  expressTracingMiddleware,
  errorTracingMiddleware,
};
