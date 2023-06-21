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

        guard let presentingWindow = NSApplication.shared.windows.first else {
          print("There is no presenting window!")
          return
        }

        GIDSignIn.sharedInstance.restorePreviousSignIn { user, error in
            if error != nil || user == nil {
                print("Not signed in")
                GIDSignIn.sharedInstance.signIn(withPresenting: presentingWindow, hint: nil, additionalScopes: ["https://www.googleapis.com/auth/drive"]) { signInResult, error in
                    guard let signInResult = signInResult else {
                        print("Error! \(String(describing: error))")
                        return
                    }
                    print("Signin Success")
                    print(signInResult)
                    print(signInResult.user.accessToken.tokenString)
                    print(signInResult.user.profile!.email)
                    print(GIDSignIn.sharedInstance.currentUser!.accessToken.tokenString)
                    self.listDirectory(user: signInResult.user)
                }
            } else {
                print("Restore success")
                print(user!.accessToken.tokenString)
                print(user!.profile!.email)
                self.listDirectory(user: user!)
            }
          }
    }

    func listDirectory(user: GIDGoogleUser) {
        self.service.authorizer = user.fetcherAuthorizer
        let query = GTLRDriveQuery_FilesList.query()
        query.pageSize = 100
        query.q = "'1DC9vuuiDDMyLccaAH8KAf_Akrk1QQ7Pb' in parents"
        //query.q = "'root' in parents"
        //query.q = "'root' in parents and mimeType != 'application/vnd.google-apps.folder'"
        //while true {
        //    print("here")
        //}
        runQuery(query: query)
    }

    func runQuery(query: GTLRDriveQuery_FilesList) {
        let raw_query = query.copy() as! GTLRDriveQuery_FilesList
        self.service.executeQuery(query) { (ticket, result, error) in
            print(error)
            let res = result as? GTLRDrive_FileList
            print(res, "#Files", res!.files?.count)
            for f in res!.files! {
                print(f)
            }
            if res?.nextPageToken != nil {
                raw_query.pageToken = res?.nextPageToken
                self.runQuery(query: raw_query)
            }
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

