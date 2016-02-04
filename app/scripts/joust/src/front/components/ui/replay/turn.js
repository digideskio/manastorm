(function() {
  var React, ReactCSSTransitionGroup, SubscriptionList, Turn, _;

  React = require('react');

  SubscriptionList = require('../../../../subscription-list');

  ReactCSSTransitionGroup = require('react-addons-css-transition-group');

  _ = require('lodash');

  Turn = React.createClass({
    render: function() {
      if (!this.props.replay) {
        return null;
      }
      return React.createElement("div", {
        "className": "current-turn",
        "onClick": this.props.onClick
      }, React.createElement("span", null, this.props.replay.getCurrentTurnString()));
    }
  });

  module.exports = Turn;

}).call(this);
