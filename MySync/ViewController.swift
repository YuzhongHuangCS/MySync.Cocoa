//
//  ViewController.swift
//  MySync
//
//  Created by Yuzhong Huang on 6/20/23.
//

import Cocoa
import GoogleSignIn
import GoogleAPIClientForREST_Drive


class ViewController: NSViewController {
    var service: GTLRDriveService = GTLRDriveService()

    @IBAction func LoginClicked(_ sender: NSButton) {
        print("LoginClicked")
        Task {
            if self.service.authorizer == nil {
                try await initDriveService()
            }

            try await listDirectory()
        }
    }

    func listDirectory() async throws {
        let query = GTLRDriveQuery_FilesList.query()
        //query.q = "'root' in parents"
        query.q = "'1DC9vuuiDDMyLccaAH8KAf_Akrk1QQ7Pb' in parents"
        repeat {
            let result = try await executeQueryAsync(query: query.copy() as! GTLRDriveQuery_FilesList)
            print(result, "#Files", result.files!.count)
            for f in result.files! {
                print(f)
            }
            query.pageToken = result.nextPageToken
        } while (query.pageToken != nil)
    }

    func executeQueryAsync(query: GTLRDriveQuery_FilesList) async throws -> GTLRDrive_FileList {
        try await withCheckedThrowingContinuation { continuation in
            self.service.executeQuery(query) { (ticket, result, error) in
                continuation.resume(with: Result<GTLRDrive_FileList, Error> {
                    if error != nil {
                        throw error!
                    }
                    return result as! GTLRDrive_FileList
                })
            }
        }
    }

    func initDriveService() async throws {
        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            print("Has Previous SignIn")
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            self.service.authorizer = user.fetcherAuthorizer
            print(user.profile!.email)
            print(user.accessToken.expirationDate!)
            print("Restore Success")
        } else {
            print("Run SignIn")
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: NSApplication.shared.windows.first!, hint: nil, additionalScopes: ["https://www.googleapis.com/auth/drive"])
            self.service.authorizer = signInResult.user.fetcherAuthorizer
            print("SignIn Success")
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
    }

    override var representedObject: Any? {
        didSet {
        // Update the view, if already loaded.
        }
    }


}

