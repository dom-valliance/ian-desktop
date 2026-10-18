// Validates responses against the contract document itself, independently of the Zod schemas that
// were generated from it. Ajv 2020 reads the OpenAPI 3.1 schemas directly. `discriminator` is an
// annotation here: Ajv rejects its `mapping`, and each union member's single-value `kind` or
// `type` enum already keeps `oneOf` unambiguous (contract/README.md).
import { Ajv2020, type ValidateFunction } from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const CONTRACT_PATH = fileURLToPath(
  new URL('../../../contract/ian-desktop.v1.yaml', import.meta.url),
);
const DOCUMENT_ID = 'https://contract.invalid/ian-desktop.v1';
const OPENAPI_ROOT_KEYWORDS = [
  'openapi',
  'info',
  'servers',
  'security',
  'tags',
  'paths',
  'components',
];
const METHODS = ['get', 'post', 'patch', 'put', 'delete'] as const;

type Json = null | boolean | number | string | Json[] | { [key: string]: Json };
type JsonObject = { [key: string]: Json };

export interface Operation {
  operationId: string;
  method: (typeof METHODS)[number];
  path: string;
}

export interface Validation {
  ok: boolean;
  errors: string[];
}

function isObject(value: Json | undefined): value is JsonObject {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

const escapePointer = (segment: string): string =>
  segment.replaceAll('~', '~0').replaceAll('/', '~1');

export class ContractValidator {
  private readonly document: JsonObject;
  private readonly ajv: Ajv2020;
  private readonly compiled = new Map<string, ValidateFunction>();

  constructor(path: string = CONTRACT_PATH) {
    this.document = parse(readFileSync(path, 'utf8')) as JsonObject;
    this.ajv = new Ajv2020({ strict: true, strictTypes: false, allErrors: true });
    addFormats.default(this.ajv);
    this.ajv.addKeyword({ keyword: 'discriminator', schemaType: 'object' });
    this.ajv.addKeyword({ keyword: 'example' });
    // The document is registered whole so `$ref` pointers resolve; its OpenAPI sections are not
    // JSON Schema keywords.
    for (const keyword of OPENAPI_ROOT_KEYWORDS) this.ajv.addKeyword({ keyword });
    this.ajv.addSchema({ ...this.document, $id: DOCUMENT_ID });
  }

  /** Every operation the contract defines, for checking that tests cover them all. */
  operations(): Operation[] {
    const paths = this.document.paths;
    if (!isObject(paths)) return [];
    const operations: Operation[] = [];
    for (const [path, item] of Object.entries(paths)) {
      if (!isObject(item)) continue;
      for (const method of METHODS) {
        const operation = item[method];
        if (isObject(operation) && typeof operation.operationId === 'string') {
          operations.push({ operationId: operation.operationId, method, path });
        }
      }
    }
    return operations;
  }

  /** The status codes the contract defines for an operation. */
  statuses(method: string, path: string): string[] {
    const responses = this.node(['paths', path, method, 'responses']);
    return isObject(responses) ? Object.keys(responses) : [];
  }

  /** Validates a value against a named schema in `components.schemas`. */
  validateSchema(name: string, value: unknown): Validation {
    return this.run(`#/components/schemas/${name}`, value);
  }

  /**
   * Checks that the contract defines this status and content type for the operation, and that the
   * body satisfies the schema. A response with no content must have an empty body.
   */
  validateResponse(
    method: string,
    path: string,
    status: number,
    contentType: string | null,
    body: unknown,
  ): Validation {
    const where = `${method.toUpperCase()} ${path} ${String(status)}`;
    const base = ['paths', path, method, 'responses', String(status)];
    let pointer = this.followRefs(base);
    if (pointer === null)
      return { ok: false, errors: [`${where}: the contract defines no such status`] };
    const response = this.node(pointer.split('/').slice(1).map(decodePointer));
    const content = isObject(response) ? response.content : undefined;
    if (!isObject(content)) {
      const empty = body === undefined || body === '' || body === null;
      return empty
        ? { ok: true, errors: [] }
        : { ok: false, errors: [`${where}: expected no body`] };
    }
    const mediaType = (contentType ?? '').split(';')[0]?.trim() ?? '';
    const media = content[mediaType];
    if (!isObject(media)) {
      return {
        ok: false,
        errors: [
          `${where}: content type "${mediaType}" is not one of ${Object.keys(content).join(', ')}`,
        ],
      };
    }
    if (!isObject(media.schema)) return { ok: true, errors: [] };
    pointer = `${pointer}/content/${escapePointer(mediaType)}/schema`;
    const result = this.run(pointer, body);
    return { ok: result.ok, errors: result.errors.map((error) => `${where}: ${error}`) };
  }

  private run(pointer: string, value: unknown): Validation {
    let validate = this.compiled.get(pointer);
    if (!validate) {
      validate = this.ajv.compile({ $ref: `${DOCUMENT_ID}${pointer}` });
      this.compiled.set(pointer, validate);
    }
    if (validate(value)) return { ok: true, errors: [] };
    return {
      ok: false,
      errors: (validate.errors ?? []).map(
        (error) => `${error.instancePath || '/'} ${error.message ?? 'is invalid'}`,
      ),
    };
  }

  private node(segments: string[]): Json | undefined {
    let current: Json | undefined = this.document;
    for (const segment of segments) {
      if (!isObject(current)) return undefined;
      current = current[segment];
    }
    return current;
  }

  /** Follows `$ref` objects from a location to the object they name; returns its JSON pointer. */
  private followRefs(segments: string[]): string | null {
    let pointer = `#/${segments.map(escapePointer).join('/')}`;
    for (let hops = 0; hops < 10; hops += 1) {
      const target = this.node(pointer.split('/').slice(1).map(decodePointer));
      if (target === undefined) return null;
      if (isObject(target) && typeof target.$ref === 'string') {
        pointer = target.$ref;
        continue;
      }
      return pointer;
    }
    return null;
  }
}

function decodePointer(segment: string): string {
  return segment.replaceAll('~1', '/').replaceAll('~0', '~');
}
