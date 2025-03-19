// The Swift Programming Language
// https://docs.swift.org/swift-book

import SwiftUI

public protocol LightweightLoginViewModel: Sendable {
        
    var loginPrompt: String { get }
    var loginPromptIcon: Image { get }
    var loginPromptIconColor: Color { get }
    
    var processButtonTitle: String { get }

    var dismissDelay: Duration { get }
    
    func processLogin(username: String, password: String) async throws
  
    func validate(username: String) -> Bool
    func validate(password: String) -> Bool
    
    func processButtonEnabled(username: String, password: String) -> Bool
}

public extension LightweightLoginViewModel {
    
    func validate(username: String) -> Bool {
        !username.isEmpty
    }
    
    func validate(password: String) -> Bool {
        !password.isEmpty
    }
    
    var processButtonTitle: String { "Done" }
    
    func processButtonEnabled(username: String, password: String) -> Bool {
        validate(username: username) && validate(password: password)
    }
}

// MARK: -

public struct LightweightLoginView
<Model: LightweightLoginViewModel,
 CancelButton: View>
: View {
        
    let model: Model
    let verticalSpacing: Bool
    
    let cancelButton: () -> CancelButton
    let dismissUI: () -> Void
    
    // TODO: bluesky allows for alternative login servers
    // so we need to allow for a server field as well
    // ATProtocolConfiguration calls it a pdsURL
    // should probably make it generic and make it be settable
    // whether it's needed or not
    @State private var username = ""
    @State private var password = ""

    @State private var error: Error?

    enum FocusedField: String {
        case username, password
    }
    @FocusState private var focusedField: FocusedField?
    
    public init(
        model: Model,
        verticalSpacing: Bool = true,
        cancelButton: @escaping () -> CancelButton,
        dismissUI: @escaping () -> Void
    ) {
        self.model = model
        self.verticalSpacing = verticalSpacing
        self.cancelButton = cancelButton
        self.dismissUI = dismissUI
    }
    
    private var usernameField: some View {
        TextField("Username", text: $username, onCommit: validateEntry)
            .autocorrectionDisabled(true)
#if !os(macOS)
            .textInputAutocapitalization(.never)
#endif
            .submitLabel(.next)
            .focused($focusedField, equals: .username)
    }

    private var passwordField: some View {
        SecureField("Password", text: $password, onCommit: validateEntry)
            .submitLabel(.done)
            .focused($focusedField, equals: .password)
    }
    
    public var body: some View {
        VStack(alignment: .leading) {
                        
            VStack(alignment: .leading) {
                
                Label {
                    Text(model.loginPrompt)
                } icon: {
                    model.loginPromptIcon
                        .foregroundStyle(model.loginPromptIconColor)
                }
                .font(.headline)

                if verticalSpacing {
                    usernameField
                    passwordField
                }
                else {
                    HStack {
                        usernameField
                        passwordField
                    }
                }
                
                if let error {
                    Text(error.localizedDescription)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }
            }
            .padding()
            
        }
        .onChange(of: username) { oldValue, newValue in
            guard !newValue.isEmpty else { return }
            error = nil
        }
        .onChange(of: password) { oldValue, newValue in
            guard !newValue.isEmpty else { return }
            error = nil
        }

        if verticalSpacing {
            Spacer()
        }
        
        HStack {
            cancelButton()
//                .buttonStyle(.borderless)
            
            Spacer()
            
            if (true == loggingIn) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            }
            
            Button(model.processButtonTitle, role: .none, action: doneButtonPressed)
                .buttonStyle(.borderedProminent)
                .disabled(!model.processButtonEnabled(username: username, password: password) || nil != loggingIn)
                .textFieldStyle(.roundedBorder)
                .padding()
                .onAppear { focusedField = .username }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal)
    }
        
    private func validateEntry() {
        error = nil
        guard model.validate(username: username) else {
            return focusedField = .username
        }
        guard model.validate(password: password) else {
            return focusedField = .password
        }
        
        Task {
            await handleLogin()
        }
    }

    private func clear() {
        username = ""
        password = ""
    }
    
    @State private var loggingIn: Bool?
    private func handleLogin() async {
        await MainActor.run {
            loggingIn = true
        }
        
        Task.detached {
            do {
                try await model.processLogin(username: username, password: password)
                await MainActor.run {
                    loggingIn = false
                    
                    Task.detached {
                        try await Task.sleep(for: model.dismissDelay)

                        await MainActor.run {
                            dismissUI()
                        }
                    }
                }
            }
            catch {
                await MainActor.run {
                    self.error = error
                    clear()
                    loggingIn = nil
                }
            }
        }
    }
        
    private func doneButtonPressed() {
        Task {
            await handleLogin()
        }
    }
}

// MARK: -

struct ExampleViewModel: LightweightLoginViewModel {
    
    let throwError: Bool
    
    init(throwError: Bool = false) {
        self.throwError = throwError
    }
    
    var loginPrompt: String { "Generic Login" }
    
    var loginPromptIcon: Image { Image(systemName: "scissors") }
    
    var loginPromptIconColor: Color { Color.teal }
                
    func processLogin(username: String, password: String) async throws {
        if throwError {
            struct Error: Swift.Error {}
            throw Error()
        }
    }
    
    var dismissDelay: Duration { .seconds(3) }
}

#Preview {
    LightweightLoginView(model: ExampleViewModel()) {
        Button("Cancel") {
            print("cancelled")
        }
    } dismissUI: {
        print("done")
    }
}

#Preview("Throwing an Error") {
    LightweightLoginView(model: ExampleViewModel(throwError: true)) {
        Button("Cancel") {
            print("cancelled")
        }
    } dismissUI: {
        print("done")
    }
}

#Preview("Compact Vertical Spacing") {
    LightweightLoginView(model: ExampleViewModel(), verticalSpacing: false) {
        Button("Cancel") {
            print("cancelled")
        }
    } dismissUI: {}
}
