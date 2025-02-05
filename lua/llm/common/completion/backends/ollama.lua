local job = require("plenary.job")
local state = require("llm.state")
local utils = require("llm.common.completion.utils")
local LOG = require("llm.common.log")

local ollama = {}

function ollama.parse(chunk, assistant_output)
  local success, err = pcall(function()
    -- for /api/generate
    -- assistant_output = chunk.response
    -- for /v1/completions
    assistant_output = chunk.choices[1].text
  end)

  if success then
    return assistant_output
  else
    LOG:ERROR("Error occurred:" .. err)
    return ""
  end
end

function ollama.request(opts)
  utils.terminate_all_jobs()
  local LLM_KEY = os.getenv("LLM_KEY")
  local LLM_AUTH_STRAT = os.getenv("LLM_AUTH_STRAT")

  local authorization_strategy = "Bearer"
  if LLM_AUTH_STRAT ~= nil then
    authorization_strategy = LLM_AUTH_STRAT
  end

  local authorization = "Authorization: " .. authorization_strategy .. " " .. LLM_KEY

  if LLM_KEY == "NONE" or LLM_KEY == "" then
    authorization = ""
  end

  local body = {
    model = opts.model,
    stream = opts.stream,
  }
  if opts.fim then
    body["prompt"] = opts.prompt
    body["suffix"] = opts.suffix
  end
  if opts.max_tokens then
    body["max_tokens"] = opts.max_tokens
  end

  local _args = {
    "-L",
    opts.url,
    "-N",
    "-X",
    "POST",
    "-H",
    "Content-Type: application/json",
    "-H",
    authorization,
    "--max-time",
    opts.timeout,
    "-d",
    vim.fn.json_encode(body),
  }

  for i = 0, opts.n_completions - 1 do
    local assistant_output = ""
    local new_job = job:new({
      command = "curl",
      args = _args,
      on_stdout = vim.schedule_wrap(function(_, data)
        if data == nil or data:sub(1, 1) ~= "{" then
          return
        end
        local success, result = pcall(vim.json.decode, data)
        if success then
          assistant_output = ollama.parse(result, assistant_output)
        else
          LOG:ERROR("Error occurred:" .. result)
        end
      end),
      on_exit = vim.schedule_wrap(function()
        if assistant_output and assistant_output ~= "" then
          LOG:TRACE("Assistant output: " .. assistant_output)
          state.completion.contents[i] = assistant_output
          if opts.exit_handler then
            opts.exit_handler({ state.completion.contents[i] })
          end
        end
      end),
    })
    table.insert(state.completion.jobs, new_job)
    new_job:start()
  end
end

return ollama
