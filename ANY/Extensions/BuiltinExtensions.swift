/// Every first-party extension, in the order their commands appear in the empty state.
enum BuiltinExtensions {
    static var all: [any ANYExtension] {
        [
            ApplicationsExtension(),
            ClipboardExtension(),
            SystemExtension(),
            CalculatorExtension(),
            TranslateExtension(),
            WebSearchExtension(),
            CoreExtension(),
        ]
    }
}
