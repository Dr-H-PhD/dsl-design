-- Lua filter to convert callout patterns to styled boxes
-- Patterns: > **Tip:** ..., > **Warning:** ..., > **Note:** ..., > **Info:** ...

function BlockQuote(el)
  local first = el.content[1]
  if first and first.t == "Para" then
    local inlines = first.content
    if inlines[1] and inlines[1].t == "Strong" then
      local strong_content = pandoc.utils.stringify(inlines[1])

      local box_type = nil
      if strong_content:match("^Tip:?$") then
        box_type = "tipbox"
      elseif strong_content:match("^Warning:?$") then
        box_type = "warningbox"
      elseif strong_content:match("^Note:?$") then
        box_type = "notebox"
      elseif strong_content:match("^Info:?$") then
        box_type = "infobox"
      elseif strong_content:match("^Important:?$") then
        box_type = "warningbox"
      elseif strong_content:match("^Caution:?$") then
        box_type = "warningbox"
      end

      if box_type then
        -- Remove the label from content
        local new_inlines = {}
        local skip_space = true
        for i = 2, #inlines do
          if skip_space and inlines[i].t == "Space" then
            skip_space = false
          else
            table.insert(new_inlines, inlines[i])
          end
        end

        -- Build new content
        local new_content = pandoc.List()
        new_content:insert(pandoc.Para(new_inlines))
        for i = 2, #el.content do
          new_content:insert(el.content[i])
        end

        -- Return raw LaTeX
        local latex_begin = "\\begin{" .. box_type .. "}\n"
        local latex_end = "\n\\end{" .. box_type .. "}"

        return {
          pandoc.RawBlock("latex", latex_begin),
          pandoc.Div(new_content),
          pandoc.RawBlock("latex", latex_end)
        }
      end
    end
  end
  return el
end
