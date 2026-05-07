import Foundation
import JMESPath

// MARK: - Project-specific JMESPath functions

/// `string lower(string $value)`
/// Returns the input string lowercased. Project-specific extension that mirrors
/// the AWS CLI's `lower()` extension. Lets you write case-insensitive comparisons
/// like `[?contains(lower(title), 'meeting')]` without spec gymnastics.
public struct LowerFunction: JMESFunction {
    public static var signature: FunctionSignature { .init(inputs: .string) }
    public static func evaluate(args: [JMESVariable], runtime: JMESRuntime) -> JMESVariable {
        switch args[0] {
        case .string(let s):
            return .string(s.lowercased())
        default:
            preconditionFailure()
        }
    }
}

/// `string upper(string $value)`
/// Returns the input string uppercased. Companion to `lower()`.
public struct UpperFunction: JMESFunction {
    public static var signature: FunctionSignature { .init(inputs: .string) }
    public static func evaluate(args: [JMESVariable], runtime: JMESRuntime) -> JMESVariable {
        switch args[0] {
        case .string(let s):
            return .string(s.uppercased())
        default:
            preconditionFailure()
        }
    }
}

/// Shared runtime registered with the project's custom functions.
/// All JMESPath evaluations in CLI / MCP go through this so the extensions
/// are available everywhere.
public enum JMESRuntimeFactory {
    public static func makeRuntime() -> JMESRuntime {
        let runtime = JMESRuntime()
        runtime.registerFunction("lower", function: LowerFunction.self)
        runtime.registerFunction("upper", function: UpperFunction.self)
        return runtime
    }
}
