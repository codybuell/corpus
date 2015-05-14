// Copyright 2015-present Greg Hurrell. All rights reserved.
// Licensed under the terms of the MIT license.

'use strict';

import React from 'react';
import autobind from 'autobind-decorator';
import cx from 'classnames';

const styles = {
  root: {
    background: 'linear-gradient(90deg, #f8f8f8, #e9e9e9)',
    borderLeft: '1px solid #c3c3c3',
    borderRight: '1px solid #bebebe',
    flexGrow: 0,
    outline: 0,
    width: '8px',
  },
};

export default class Separator extends React.Component {
  static propTypes = {
    onMouseMove: React.PropTypes.func,
  };

  @autobind
  _onMouseDown() {
    const onMouseMove = this.props.onMouseMove;
    const onMouseUp = () => {
      document.removeEventListener('mousemove', onMouseMove);
      document.removeEventListener('mouseup', onMouseUp);
      document.body.classList.remove('grabbing');
    };

    document.addEventListener('mousemove', onMouseMove);
    document.addEventListener('mouseup', onMouseUp);
    document.body.classList.add('grabbing');
  }

  shouldComponentUpdate(nextProps, nextState) {
    return false;
  }

  render() {
    return (
      <div
        className="separator"
        onMouseDown={this._onMouseDown}
        style={styles.root}
        tabIndex={-1}
      />
    );
  }
}
