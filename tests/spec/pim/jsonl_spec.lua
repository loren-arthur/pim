local jsonl = require("pim.jsonl")

-- Collector helper: returns a fresh state table and a dispatcher that appends
-- events to it. Mirrors the way rpc.lua interacts with the parser.
local function make_collector()
  local state = { pending = "", events = {} }
  return state, function(e)
    table.insert(state.events, e)
  end
end

describe("pim.jsonl.consume_chunk", function()
  it("emits a single complete event from one chunk", function()
    local state, dispatch = make_collector()
    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      '{"type":"a","x":1}\n',
      dispatch
    )
    assert.are.same({ { type = "a", x = 1 } }, state.events)
    assert.are.same("", state.pending)
  end)

  it("preserves partial bytes between chunks", function()
    local state, dispatch = make_collector()
    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      '{"a":1}\n{"b',
      dispatch
    )
    assert.are.same({ { a = 1 } }, state.events)
    assert.are.same('{"b', state.pending)

    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      '":2}\n',
      dispatch
    )
    assert.are.same({ { a = 1 }, { b = 2 } }, state.events)
    assert.are.same("", state.pending)
  end)

  it("skips empty lines", function()
    local state, dispatch = make_collector()
    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      '\n{"x":1}\n\n\n{"y":2}\n',
      dispatch
    )
    assert.are.same(2, #state.events)
    assert.are.same({ x = 1 }, state.events[1])
    assert.are.same({ y = 2 }, state.events[2])
  end)

  it("strips a trailing \\r before decoding", function()
    local state, dispatch = make_collector()
    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      '{"x":1}\r\n{"y":2}\r\n',
      dispatch
    )
    assert.are.same({ { x = 1 }, { y = 2 } }, state.events)
  end)

  it("emits pim_parse_error for invalid JSON", function()
    local state, dispatch = make_collector()
    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      'not-json\n{"x":1}\n',
      dispatch
    )
    assert.are.same(2, #state.events)
    assert.are.same("pim_parse_error", state.events[1].type)
    assert.are.same("not-json", state.events[1].line)
    assert.are.same({ x = 1 }, state.events[2])
  end)

  it("forwards the original line verbatim in pim_parse_error", function()
    local state, dispatch = make_collector()
    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      '{"unterminated"\n',
      dispatch
    )
    assert.are.same(1, #state.events)
    assert.are.same("pim_parse_error", state.events[1].type)
    assert.are.same('{"unterminated"', state.events[1].line)
  end)

  it("handles many events in one chunk", function()
    local state, dispatch = make_collector()
    local chunk = ""
    for i = 1, 50 do
      chunk = chunk .. string.format('{"i":%d}\n', i)
    end
    jsonl.consume_chunk(
      function()
        return state.pending
      end,
      function(p)
        state.pending = p
      end,
      chunk,
      dispatch
    )
    assert.are.same(50, #state.events)
    assert.are.same({ i = 50 }, state.events[50])
  end)
end)
