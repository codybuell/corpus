/**
 * @copyright Copyright (c) 2019-present Greg Hurrell
 * @license MIT
 */

type FrozenSet<T> = import('@wincent/frozen-set').default<T>;

type Action =
  | Readonly<{
      type: 'load';
      notes: readonly Note[];
    }>
  | Readonly<{
      type: 'filter';
      query: string;
    }>;

type Config = {
  notesDirectory: string;
  noteFontFamily: string;
  noteFontSize: string;
};

/**
 * JSON
 *
 * @see https://www.json.org/
 */

// eslint-disable-next-line @typescript-eslint/no-empty-interface
interface JSONArray extends Array<JSONValue> {}

type JSONObject = {[member: string]: JSONValue};
type JSONValue = JSONArray | JSONObject | boolean | null | number | string;

type Note = {
  body: string;
  mtime: number;
  path: string;
  readonly id: number; // really UUID
  tags: Set<string>;
  text: string;
  title: string;
  version: number;
};

type Store = {
  readonly filteredNotes: Readonly<Note[]>;
  readonly notes: Readonly<Note[]>;
  readonly selectedNotes: FrozenSet<Note>;
};

type Styles<T extends string = 'root'> = Readonly<
  {
    [name in T]: React.CSSProperties;
  }
>;

// Counterpart to Readonly<T>.
type Writable<T> = {
  -readonly [K in keyof T]: T[K];
};
