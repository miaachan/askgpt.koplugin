local _ = require("gettext")
local ButtonDialogTitle = require("ui/widget/buttondialogtitle")
local ChatGPTViewer = require("chatgptviewer")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local UIManager = require("ui/uimanager")

local queryChatGPT = require("gpt_query")

local CONFIGURATION = nil
local buttons, input_dialog

local success, result = pcall(function() return require("configuration") end)
if success then
  CONFIGURATION = result
else
  print("configuration.lua not found, skipping...")
end

local function _queryChatGPT(message_history, Ok, Err)
  local success, result = queryChatGPT(message_history)
  if success then
    Ok(result)
  else
    Err(result)
  end
end

local function showInfoMessage(text, timeout)
  UIManager:show(InfoMessage:new{
    text = text,
    timeout = timeout or 3
  })
end

local function showLoadingDialog()
  showInfoMessage(_("Loading..."), 0.1)
end

local function createResultText(highlightedText, message_history)
  local result_text = _("Highlighted text: ") .. "\"" .. highlightedText .. "\"\n\n"

  for i = 2, #message_history do
    if message_history[i].role == "user" then
      result_text = result_text .. _("User: ") .. message_history[i].content .. "\n\n"
    else
      result_text = result_text .. _("ChatGPT: ") .. message_history[i].content .. "\n\n"
    end
  end

  return result_text
end

local function handleNewQuestion(chatgpt_viewer, question, highlightedText, message_history)
  table.insert(message_history, {
    role = "user",
    content = question
  })

  local success, result = queryChatGPT(message_history)

  if not success then
    UIManager:show(InfoMessage:new{
      text = result, -- Show error message
      timeout = 3,
    })
    return
  end

  table.insert(message_history, {
    role = "assistant",
    content = result
  })

  local result_text = createResultText(highlightedText, message_history)
  chatgpt_viewer:update(result_text)
end

local function showPromptSelectionDialog(callback, prompts)
  local prompt_buttons = {}
  local prompt_dialog

  for _i, prompt in ipairs(prompts) do
    table.insert(prompt_buttons, {{
      text = _(prompt.name),
      callback = function()
        UIManager:close(prompt_dialog)
        showLoadingDialog()

        UIManager:scheduleIn(0.1, function()
          callback(prompt.prompt)
        end)
      end
    }})
  end

  table.insert(prompt_buttons, {{
    text = _("Cancel"),
    id = "close",
    callback = function()
      UIManager:close(prompt_dialog)
    end
  }})

  prompt_dialog = ButtonDialogTitle:new{
    title = _("Select a custom prompt"),
    title_align = "center",
    buttons = prompt_buttons
  }

  UIManager:show(prompt_dialog)
end

local function executeCustomPrompt(highlightedText, prompt, message_history, handleNewQuestionWrapper)
  table.insert(message_history, {
    role = "user",
    content = prompt .. ": " .. highlightedText
  })

  _queryChatGPT(message_history, function (result)
    table.insert(message_history, {
      role = "assistant",
      content = result
    })
    local result_text = createResultText(highlightedText, message_history)
    local chatgpt_viewer = ChatGPTViewer:new {
      title = _("Custom Prompt Response"),
      text = result_text,
      onAskQuestion = handleNewQuestionWrapper
    }
    UIManager:show(chatgpt_viewer)
  end, function(err)
    showInfoMessage(err)
  end)

end

local function translateText(highlightedText, target_language, message_history, handleNewQuestionWrapper)
  showLoadingDialog()

  UIManager:scheduleIn(0.1, function()
    local translation_message = {
      role = "user",
      content = "Translate the following text to " .. target_language .. ": " .. highlightedText
    }
    local history = {
      {
        role = "system",
        content = "You are a helpful translation assistant. Provide direct translations without additional commentary."
      },
      translation_message
    }

    _queryChatGPT(history, function(result) 
      table.insert(message_history, {
        role = "user",
        content = "Translate to " .. CONFIGURATION.features.translate_to .. ": " .. highlightedText
      })
  
      table.insert(message_history, {
        role = "assistant",
        content = result
      })
      local result_text = createResultText(highlightedText, message_history)
      local chatgpt_viewer = ChatGPTViewer:new {
        title = _("Translation"),
        text = result_text,
        onAskQuestion = handleNewQuestionWrapper
      }
      UIManager:show(chatgpt_viewer)
    end, function(err)
        showInfoMessage(err)
    end)
  end)
end

local function showChatGPTDialog(ui, highlightedText, message_history)
  local title, author =
    ui.document:getProps().title or _("Unknown Title"),
    ui.document:getProps().authors or _("Unknown Author")
  local message_history = message_history or {{
    role = "system",
    content = "The following is a conversation with an AI assistant. The assistant is helpful, creative, clever, and very friendly. Answer as concisely as possible."
  }}

  local function handleNewQuestionWrapper(chatgpt_viewer, question)
    handleNewQuestion(chatgpt_viewer, question, highlightedText, message_history)
  end

  buttons = {
    {
      text = _("Ask"),
      callback = function()
        local question = input_dialog:getInputText()
        UIManager:close(input_dialog)
        showLoadingDialog()

        UIManager:scheduleIn(0.1, function()
          table.insert(message_history, {
            role = "user",
            content = "I'm reading something titled '" .. title .. "' by " .. author ..
              ". I have a question about the following highlighted text: " .. highlightedText
          })
          table.insert(message_history, {
            role = "user",
            content = question
          })
          _queryChatGPT(message_history, function(result)
              table.insert(message_history, {
                  role = "assistant",
                  content = result
              })
              local result_text = createResultText(highlightedText, message_history)

              local chatgpt_viewer = ChatGPTViewer:new {
                title = _("AskGPT"),
                text = result_text,
                onAskQuestion = handleNewQuestionWrapper
              }
    
              UIManager:show(chatgpt_viewer)
          end, function(err)
              showInfoMessage(err)
          end)
        end)
      end
    }
  }

  if CONFIGURATION then

    if CONFIGURATION.prompts then
      table.insert(buttons, {
        text = _("Custom Prompt"),
        callback = function()
          showPromptSelectionDialog(function(selected_prompt)
            executeCustomPrompt(highlightedText, selected_prompt, message_history, handleNewQuestionWrapper)
          end, CONFIGURATION.prompts)
        end
      })
    end

    if CONFIGURATION.features and CONFIGURATION.features.translate_to then
      table.insert(buttons, {
        text = _("Translate"),
        callback = function()
          translateText(highlightedText, CONFIGURATION.features.translate_to, message_history, handleNewQuestionWrapper)
        end
      })
    end

  end

  table.insert(buttons, {
    text = _("Cancel"),
    id = "close",
    callback = function()
      UIManager:close(input_dialog)
    end
  })

  input_dialog = InputDialog:new{
    title = _("Ask a question about the highlighted text"),
    input_hint = _("Type your question here..."),
    input_type = "text",
    buttons = {buttons}
  }
  UIManager:show(input_dialog)
end

return showChatGPTDialog
