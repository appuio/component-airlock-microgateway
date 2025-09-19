local result = {
  local this = self,
  unwrap: function()
    if this._type == 'ok' then
      this._result
    else
      error this._error
  ,
  unwrapOr: function(or)
    if this._type == 'ok' then
      this._result
    else
      std.trace('unwrapOr: discarded error: %s' % this._error, or)
  ,
  match: function(ok=function(res) res, err=function(err) err)
    if this._type == 'ok' then
      ok(this._result)
    else
      err(this._error),
};

local ok(res) = result {
  _result: res,
  _type: 'ok',
};

local err(msg) = result {
  _error: msg,
  _type: 'error',
};


[
  ok('World').match(
    ok=function(res) 'Hello, %s!' % res,
  ),
  err('Everyone').match(
    ok=function(res) 'Hello, %s!' % res,
  ),
]
