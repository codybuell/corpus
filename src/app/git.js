/**
 * Copyright 2015-present Greg Hurrell. All rights reserved.
 * Licensed under the terms of the MIT license.
 *
 * @flow
 */

'use strict';

import run from './run';

function git(...args: Array<string>): Promise {
  return run('git', ...args);
}

export default git;
