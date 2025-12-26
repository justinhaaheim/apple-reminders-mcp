# Important guidelines

# Use a scratchpad

- Always use a "scratchpad" markdown document to outline your work plan, track your progress, and provide yourself important notes or reminders (unless I explicitly instruct you to skip the scratchpad doc).
  - This scratchpad is for YOU, so that you can maintain a clear focus across long conversations or separate conversation threads. Keep it focused on what is helpful to YOU, add to it freely, update it regularly, and remove/fix content when needed.
  - All scratchpad markdown docs should be in `docs/plans/`
  - If this work stream already has a document in-progress I will link it explicitly.
  - Otherwise create a new doc with a filename that includes today’s date (you must run the `date` terminal command to get the current date) using this format: `YYYY-MM-DD_name-of-work-stream.md`

# Make a plan

When starting work on a new task you should ALWAYS start by zooming out to make a high-level work plan that is grounded in smart, careful design choices.

- ALWAYS make this plan and share it with me explicitly in our chat before starting your work.
- Wait to begin coding until I've OK'ed your plan

When making your plan put on your "Savvy, discerning senior engineer hat":

- Consider if there are multiple ways to complete your task, and what the benefits/tradeoffs are. If you see a simpler/better way to do something, tell me!
- ALWAYS prioritize the approaches that...
  - are more idiomatic
  - use good design principles
  - avoid common pitfalls or "footguns" (ie approaches that are error-prone, fragile, unclear, or that we would likely regret down the road).

# Stay focused

- Focus on addressing the task I’ve given you in the smartest, most direct way possible.
- Always prioritize getting your change _working_ over fixing lint/typescript issues that arise. Return to fix the lint/ts issues at the end.
- Do not change anything that is not directly related to the task you are working on. Do not alter/remove comments or code unless it is required for your task, or are explicitly instructed to.

# Use good style

- **NEVER disable a lint rule unless explicitly authorized to do so.**
  - The lint rules for this project were carefully chosen for a reason. These rules help prevent anti-patterns, mistakes, and hard-to-debug code.
  - You should focus on getting your change WORKING first, but always come back and address lint/ts issues
  - You should always attempt to _improve the code_ in order to address the warnings/errors.
  - If you get stuck addressing a lint/ts issue you can move onto the next one, but ALWAYS explicitly flag the issue to me if you needed to skip over it.

- Use `null` when a particular property is absent (instead of an empty string, empty array, the number 0, etc.). For instance, if an object has a property `uri` that is not known now, but will be known in the future, then `uri` should be set to `null` instead of an empty string. This improves clarity and reduces bugs. Note that you may need to update the typescript type definition, and accommodate the new null possibility at other points in the code.

- When creating a new file/component check the codebase for code that already exists to fulfill that purpose. If you are uncertain whether to change existing code or create new code, ask me in our chat.

- Use functional, declarative programming. Never create javascript classes unless specifically requested. Prefer the module pattern over classes.

- Use the function declaration syntax for functions/components at the top level of a file. Otherwise use whatever is most idiomatic.

## React:

- Use functional components
- Rigorously follow good react patterns, and avoid anti-patterns
- Avoid patterns that cause React to re-render needlessly
- Memoize callbacks/objects with `useCallback` or `useMemo`
- NEVER NEVER NEVER disable the `exhaustive-deps` lint rule that applies to `useEffect`, `useCallback`, `useMemo`, etc. This is an anti-pattern, and is very likely to introduce bugs that are hard to detect.
  - Instead write explicit logic. If an effect should only run once, for example, check `if (didRunRef.current) return;` at the start of the effect.
- Use `useEffect` to _synchronize a component with an external system_. Use it for code that should run _because_ the component was displayed ot the user.
  - In most other cases you should be handling things imperatively as part of an event handler

# Check your work

Check your work with `npm run signal`:

- `npm run signal` - Check for typescript, lint and formatting issues all at once

You can also use these scripts to directly check for issues:

- `npm run ts-check` - Check for typescript errors
- `npm run lint` - Check for lint issues

You can also use the tools directly via `npx`:

- `npx tsc --noEmit [file]`
- `npx eslint [file]`

Do NOT use `cd [path] && [command]` in your commands unless it is absolutely necessary. `cd` commands are blocked by default and require explicit permission, which slows us both down.

# Commit regularly

- Commit your changes regularly using `git add .` and `git commit ...`.
- Start all your commit messages with the model name and number in use in brackets (ie `[Claude 4 Sonnet] `, `[Gemini 2.5 Pro] `, etc)
- Commit any scratchpad markdown doc updates along with your code changes
