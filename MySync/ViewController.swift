//
//  ViewController.swift
//  MySync
//
//  Created by Yuzhong Huang on 6/20/23.
//

import Cocoa
import GoogleSignIn
import GoogleAPIClientForREST_Drive


class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var service = GTLRDriveService()
    var rows = [[String]]()

    @IBOutlet weak var driveTable: NSTableView!
    @IBOutlet weak var rowCount: NSTextField!
    @IBOutlet weak var pathField: NSTextField!
    @IBOutlet weak var statusField: NSTextField!

    func numberOfRows(in tableView: NSTableView) -> Int {
        return rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let cellView = tableView.makeView(withIdentifier:
            (tableColumn?.identifier)!,
            owner: self) as? NSTableCellView
        else {
            return nil
        }

        let col = tableView.tableColumns.firstIndex(of: tableColumn!)
        cellView.textField!.stringValue = rows[row][col!]

        return cellView
    }

    // Not used in View based NSTableview
    func tableView(
        _ tableView: NSTableView,
        objectValueFor tableColumn: NSTableColumn?,
        row: Int
    ) -> Any? {
        let col = tableView.tableColumns.firstIndex(of: tableColumn!)
        return rows[row][col!]
    }

    @IBAction func LoginClicked(_ sender: NSButton) {
        Task {
            if self.service.authorizer == nil {
                statusField.stringValue = "Init"
                try await initDriveService()
            }

            statusField.stringValue = "Loading"
            try await listDirectory()
            statusField.stringValue = "Done"
        }
    }

    func listDirectory() async throws {
        let query = GTLRDriveQuery_FilesList.query()
        query.q = "'root' in parents"
        //query.q = "'1DC9vuuiDDMyLccaAH8KAf_Akrk1QQ7Pb' in parents"
        //query.q = "'1b8bOEsE7LX6XGj7yZqchLW_0ykJqTLfL' in parents"
        query.fields = "nextPageToken, files(name, mimeType, size, owners, id, parents)"

        repeat {
            let result = try await executeQueryAsync(query: query.copy() as! GTLRDriveQuery_FilesList)
            for f in result.files! {
                rows.append([
                    f.name!,
                    f.mimeType!,
                    f.size != nil ? String(format: "%.2f MB", Double(truncating: f.size!) / 1024.0 / 1024.0): "",
                    (f.owners?.map({o in
                        o.displayName! + " <" + o.emailAddress! + ">"
                    }).joined(separator: "; "))!,
                    f.identifier!
                ])
            }
            driveTable.reloadData()
            rowCount.stringValue = String(rows.count)
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
