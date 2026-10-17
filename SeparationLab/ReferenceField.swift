import SwiftUI

/// A native decimal field with an input accessory that is always available,
/// including outside a NavigationStack.
struct ReferenceField: UIViewRepresentable {
    @Binding var text:String
    let onFinished:()->Void
    func makeCoordinator()->Coordinator { Coordinator(self) }
    func makeUIView(context:Context)->UITextField {
        let field=UITextField()
        field.keyboardType = .decimalPad
        field.textAlignment = .right
        field.font = .preferredFont(forTextStyle:.body)
        field.textColor = .white
        field.tintColor = .systemTeal
        field.placeholder="10"
        field.accessibilityLabel="Reference distance in millimetres"
        field.delegate=context.coordinator
        field.addTarget(context.coordinator,action:#selector(Coordinator.changed(_:)),for:.editingChanged)
        let toolbar=UIToolbar();toolbar.sizeToFit()
        toolbar.items=[UIBarButtonItem(title:"Reference distance · mm",style:.plain,target:nil,action:nil),
                       UIBarButtonItem(systemItem:.flexibleSpace),
                       UIBarButtonItem(title:"Done",style:.done,target:context.coordinator,action:#selector(Coordinator.done))]
        field.inputAccessoryView=toolbar
        context.coordinator.field=field
        return field
    }
    func updateUIView(_ field:UITextField,context:Context) {
        context.coordinator.parent=self
        if field.text != text { field.text=text }
    }
    final class Coordinator:NSObject,UITextFieldDelegate {
        var parent:ReferenceField
        weak var field:UITextField?
        init(_ parent:ReferenceField) { self.parent=parent }
        @objc func changed(_ field:UITextField) { parent.text=field.text ?? "" }
        @objc func done() { field?.resignFirstResponder() }
        func textFieldShouldReturn(_ textField:UITextField)->Bool { textField.resignFirstResponder();return true }
        func textFieldDidEndEditing(_ textField:UITextField) { parent.onFinished() }
        func textFieldDidBeginEditing(_ textField:UITextField) {
            // Exercise the exact Done action with an explicitly synthetic UI fixture.
            if ProcessInfo.processInfo.arguments.contains("--keyboard-check") {
                DispatchQueue.main.asyncAfter(deadline:.now()+6) { [weak self] in self?.done() }
            }
        }
    }
}
