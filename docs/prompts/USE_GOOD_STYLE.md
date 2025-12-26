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
