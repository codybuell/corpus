/**
 * @copyright Copyright (c) 2019-present Greg Hurrell
 * @license MIT
 */

import stripComments from '../stripComments';

it('groks simple JSON with strings', () => {
  const input = `
    {
      "foo": "string",
      "bar": 1,
    }
  `;
  expect(stripComments(input)).toEqual(input);
});

it('groks simple JSON with strings containing "//"', () => {
  const input = `
    {
      "foo": "string // not a comment",
      "bar": 1,
    }
  `;
  expect(stripComments(input)).toEqual(input);
});

it('groks simple JSON with strings containing escaped quotes', () => {
  const input = `
    {
      "foo": "string \\"stuff\\" there",
      "bar": 1,
    }
  `;
  expect(stripComments(input)).toEqual(input);
});

it('strips comments', () => {
  const input = `
    {
      // Comment here containing "stuff" and \\n escapes.
      "douglas": "crockford",
      "other": "stuff"
    }
  `;
  expect(stripComments(input)).toEqual(`
    {
      "douglas": "crockford",
      "other": "stuff"
    }
  `);
});
