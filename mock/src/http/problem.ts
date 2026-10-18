import type { FastifyReply } from 'fastify';
import { MockError } from '../domain/errors.js';

export interface ProblemBody {
  type: string;
  title: string;
  status: number;
  detail: string;
  [extension: string]: unknown;
}

export function problemBody(error: MockError): ProblemBody {
  return {
    type: 'about:blank',
    title: error.title,
    status: error.status,
    detail: error.detail,
    ...error.extensions,
  };
}

export function sendProblem(reply: FastifyReply, error: MockError): FastifyReply {
  return reply
    .status(error.status)
    .header('content-type', 'application/problem+json')
    .send(JSON.stringify(problemBody(error)));
}
