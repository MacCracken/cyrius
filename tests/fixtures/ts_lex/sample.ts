#!/usr/bin/env tsx
// v5.7.2 P1.7 regression sample — covers all P1.1-P1.6 lex features.
/**
 * JSDoc-style block comment.
 * Multi-line. JSDoc is just a slash-star-star ... star-slash pair —
 * the lexer treats it identically to a regular block comment.
 */

import { foo, bar as baz } from './module';
import type { Config, Result } from './types';

// Numeric literals: decimal, hex, oct, bin, with _ separators
const dec = 1_000_000;
const hex = 0xDEAD_BEEF;
const oct = 0o755;
const bin = 0b1010_1010;
const flt = 3.14; // float (lex treats as INT span for now; parser handles .)

// String literals + escapes
const s1 = "double quoted";
const s2 = 'single quoted';
const s3 = "with \\n escapes \\t and \\\"";

// Template literals — plain, with interp, nested, multi-line
const t1 = `plain template`;
const t2 = `hello ${dec} world`;
const t3 = `outer ${`inner ${hex}`} done`;
const t4 = `multi
line
template`;
const t5 = `obj literal in interp: ${{key: "val"}}`;

// Regex literals — context-sensitive disambiguation
const r1 = /^abc$/;
const r2 = /pattern/g;
const r3 = /[a-z0-9_]+@[a-z0-9.-]+\\.[a-z]{2,}/i;
const r4 = !/match/;          // ! prefix -> regex
const r5 = /[/]/;             // / inside char class doesn't close

// Division (primary context — should NOT lex as regex)
const div1 = dec / 2;
const div2 = (dec + hex) / 3;
const div3 = arr[0] / 10;
const div4 = obj.from / 1000; // contextual keyword 'from' as property

// Postfix non-null assertion (the BANG walk-back case)
function nonNull(arr: number[]): number {
  return arr[0]! / 2;          // ]! / -> primary, then SLASH (not regex)
}

// Multi-char operators
const eq = a === b;
const ne = a !== b;
const le = a <= b;
const ge = a >= b;
const sh = a << 2;
const sr = a >> 2;
const usr = a >>> 2;
const land = a && b;
const lor = a || b;
const nc = a ?? b;
const oc = a?.b;
const pow = a ** 2;
const arrow = (x: number) => x + 1;
const spread = [...arr];
const inc = i++;
const dec2 = j--;

// Compound assignments
let x = 1;
x += 2; x -= 1; x *= 3; x /= 2; x %= 5;
x &= 1; x |= 2; x ^= 4; x <<= 1; x >>= 1; x >>>= 1;
x **= 2; x &&= 1; x ||= 0; x ??= 0;

// Class with members
class User {
  private name: string = "anon";
  protected id: number = 0;
  public readonly key: string;
  static count: number = 0;

  constructor(name: string) {
    this.name = name;
    this.key = `user-${User.count++}`;
  }

  get displayName(): string { return this.name; }
  set displayName(v: string) { this.name = v; }

  greet(): string {
    return `hi ${this.name}, your id is ${this.id}`;
  }

  matches(re: RegExp = /./): boolean {
    return re.test(this.name);
  }
}

// Generics + utility types
function pick<T, K extends keyof T>(obj: T, keys: K[]): Pick<T, K> {
  const result = {} as Pick<T, K>;
  for (const k of keys) {
    result[k] = obj[k];
  }
  return result;
}

// Async function with await (recognized but parser-deferred to v5.7.3)
async function fetchData(url: string): Promise<unknown> {
  const r = await fetch(url);
  return r.json();
}

// for...of, for...in
for (const item of arr) { console.log(item); }
for (const k in obj) { console.log(k); }

// switch with multiple cases
switch (status) {
  case 'ok': return true;
  case 'fail': return false;
  default: throw new Error(`unknown: ${status}`);
}

// Type alias + interface
type Callback = (err: Error | null, result?: string) => void;
interface Repo {
  readonly id: string;
  fetch(): Promise<Repo>;
}
