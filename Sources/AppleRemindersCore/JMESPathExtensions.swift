import Foundation
import JMESPath

// MARK: - Project-specific JMESPath functions

/// `string lower(string $subject)` — returns the input lowercased.
/// Mirrors the AWS CLI's `lower` extension; not part of the JMESPath spec.
public struct LowerFunction: JMESFunction {
    public static var signature: FunctionSignature { .init(inputs: .string) }
    public static func evaluate(args: [JMESVariable], runtime: JMESRuntime) -> JMESVariable {
        if case .string(let s) = args[0] {
            return .string(s.lowercased())
        }
        // FunctionSignature validation rejects non-string args before this runs.
        return .null
    }
}

/// `string upper(string $subject)` — returns the input uppercased.
/// Mirrors the AWS CLI's `upper` extension; not part of the JMESPath spec.
public struct UpperFunction: JMESFunction {
    public static var signature: FunctionSignature { .init(inputs: .string) }
    public static func evaluate(args: [JMESVariable], runtime: JMESRuntime) -> JMESVariable {
        if case .string(let s) = args[0] {
            return .string(s.uppercased())
        }
        return .null
    }
}

/// Returns a JMESRuntime preloaded with the project's custom functions
/// (`lower`, `upper`). Use this anywhere we evaluate user-supplied JMESPath
/// instead of `JMESRuntime()` so the extensions are always available.
public func makeJMESRuntime() -> JMESRuntime {
    let runtime = JMESRuntime()
    runtime.registerFunction("lower", function: LowerFunction.self)
    runtime.registerFunction("upper", function: UpperFunction.self)
    return runtime
}
