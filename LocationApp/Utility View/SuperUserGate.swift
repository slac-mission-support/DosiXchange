//
//  SuperUserGate.swift
//  LocationApp
//
//  Created by Daniel Spady on 6/17/26.
//

import UIKit

//Obfuscation-level super-user gate (not real access control) shared across
//screens. The passcode is checked against the cached Settings record, so it
//can be rotated from CloudKit without an app update.
enum SuperUserGate {

    //Pure decision: entered text must parse to an integer equal to the
    //configured passcode; empty or non-numeric input is rejected.
    static func passcodeAccepted(entered: String?, configured: Int) -> Bool {
        guard let value = Int(entered ?? "") else { return false }
        return value == configured
    }

    //Once-per-session unlock for saving Edit Record edits. A static so it is
    //app-wide and survives LocationDetails being re-instantiated per navigation;
    //it resets to false on each app launch, so the first save of a session prompts.
    static var editRecordSavesUnlocked = false
}

extension UIViewController {

    //Prompt for the super-user passcode, then run onSuccess only if it matches
    //the configured value. Shared by Reset Cache, Delete Old Cycles, Edit Record.
    func requireSuperUserPasscode(message: String, onSuccess: @escaping () -> Void) {
        let alert = UIAlertController(title: "Super User Access",
                                      message: message,
                                      preferredStyle: .alert)
        alert.addTextField { textField in
            textField.keyboardType = .numberPad
            textField.isSecureTextEntry = true
            textField.placeholder = "Passcode"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in
            let entered = alert.textFields?.first?.text
            container.settings.getSettings { settings in
                DispatchQueue.main.async {
                    if SuperUserGate.passcodeAccepted(entered: entered, configured: settings.superUserPasscodeValue) {
                        print("Super-user gate: passcode accepted")
                        onSuccess()
                    } else {
                        print("Super-user gate: passcode rejected")
                        self.presentWrongPasscode()
                    }
                }
            }
        }))
        present(alert, animated: true)
    }

    func presentWrongPasscode() {
        let alert = UIAlertController(title: "Incorrect Passcode",
                                      message: "The passcode you entered is not correct.",
                                      preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(alert, animated: true)
    }
}
