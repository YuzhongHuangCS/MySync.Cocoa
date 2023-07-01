//
//  ViewController.swift
//  MySync
//
//  Created by Yuzhong Huang on 6/20/23.
//

import Cocoa
import GoogleSignIn
import GoogleAPIClientForREST_Drive
import UniformTypeIdentifiers


class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    let FOLDER_MIME = "application/vnd.google-apps.folder"
    let DRIVE_SERVICE = GTLRDriveService()
    var PATH = [[String?]]()
    var START_TIME = TimeInterval()
    var Rows = [[String]]()

    @IBOutlet weak var driveTable: NSTableView!
    @IBOutlet weak var rowCount: NSTextField!
    @IBOutlet weak var pathField: NSTextField!
    @IBOutlet weak var statusField: NSTextField!

    func numberOfRows(in tableView: NSTableView) -> Int {
        return Rows.count
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor tableColumn: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let cellView = tableView.makeView(withIdentifier: (tableColumn?.identifier)!, owner: self) as? NSTableCellView
        else {
            return nil
        }

        let col = tableView.tableColumns.firstIndex(of: tableColumn!)
        cellView.textField!.stringValue = Rows[row][col!]

        return cellView
    }

    // Not used in View based NSTableview
    func tableView(
        _ tableView: NSTableView,
        objectValueFor tableColumn: NSTableColumn?,
        row: Int
    ) -> Any? {
        let col = tableView.tableColumns.firstIndex(of: tableColumn!)
        return Rows[row][col!]
    }

    @IBAction func LoginClicked(_ sender: NSButton) {
        Task {
            if self.DRIVE_SERVICE.authorizer == nil {
                statusField.stringValue = "Init"
                try await initDriveService()
            }

            PATH.removeAll(keepingCapacity: true)
            PATH.append(["/", nil])
            pathField.stringValue = PATH.map {$0[0]!}.joined(separator: "/")

            statusField.stringValue = "Loading"
            try await listDirectory(nil)
            statusField.stringValue = "Done"
        }
    }

    @IBAction func ParentClicked(_ sender: NSButton) {
        Task {
            if PATH.count > 1 {
                PATH.remove(at: PATH.count - 1)
                pathField.stringValue = PATH.map {$0[0]!}.joined(separator: "/")

                statusField.stringValue = "Loading"
                try await listDirectory(PATH.last![1])
                statusField.stringValue = "Done"
            }
        }
    }

    @IBAction func DownloadClicked(_ sender: NSButton) {
        Task {
            if self.DRIVE_SERVICE.authorizer != nil && driveTable.numberOfSelectedRows > 0 {
                let panel = NSOpenPanel();
                panel.canChooseFiles = false
                panel.canChooseDirectories = true
                panel.canCreateDirectories = true

                if panel.runModal() == NSApplication.ModalResponse.OK {
                    statusField.stringValue = "Downloading"

                    await withTaskGroup(of: Void.self) { group in
                        for rowIndex in driveTable.selectedRowIndexes {
                            group.addTask {
                                do {
                                    let row = await self.Rows[rowIndex]
                                    try await self.downloadFile(row[4], NSString.path(withComponents: [panel.url!.path, row[0]]))
                                } catch {
                                    print("downloadFile error:", error)
                                }
                            }
                        }
                    }

                    statusField.stringValue = "Done"
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "Please Login First"
                alert.alertStyle = NSAlert.Style.critical
                alert.runModal()
            }
        }
    }

    func downloadFile(_ fileId: String, _ filename: String) async throws {
        let query = GTLRDriveQuery_FilesGet.queryForMedia(withFileId: fileId)
        let data = try await executeQueryAsync(query: query) as! GTLRDataObject

        try data.data.write(to: NSURL.fileURL(withPath: filename))
        print("\(filename): Download Complete")
    }

    @IBAction func UploadClicked(_ sender: NSButton) {
        Task {
            if self.DRIVE_SERVICE.authorizer != nil {
                let panel = NSOpenPanel();
                panel.canChooseFiles = true
                panel.canChooseDirectories = true
                panel.allowsMultipleSelection = true

                if panel.runModal() == NSApplication.ModalResponse.OK {
                    statusField.stringValue = "Uploading"

                    await withTaskGroup(of: Void.self) { group in
                        for url in panel.urls {
                            if isDir(url.path) {
                                let uploads = await walkDirectory(url.path, self.PATH.last![1])
                                for req in uploads {
                                    group.addTask {
                                        do {
                                            try await self.uploadFile(NSURL.fileURL(withPath: req[0]), req[1])
                                        } catch {
                                            print("uploadFile error:", error)
                                        }
                                    }
                                }
                            } else {
                                group.addTask {
                                    do {
                                        try await self.uploadFile(url, self.PATH.last![1])
                                    } catch {
                                        print("uploadFile error:", error)
                                    }
                                }
                            }
                        }
                    }

                    statusField.stringValue = "Done"
                }
            } else {
                let alert = NSAlert()
                alert.messageText = "Please Login First"
                alert.alertStyle = NSAlert.Style.critical
                alert.runModal()
            }
        }
    }

    func isDir(_ path: String) -> Bool {
        var resultStorage: ObjCBool = false
        FileManager.default.fileExists(atPath: path, isDirectory: &resultStorage)
        return resultStorage.boolValue
    }

    func walkDirectory(_ path: String, _ parent: String?) async -> [[String]] {
        var ret = [[String]]()
        do {
            let driveFolder = GTLRDrive_File()
            driveFolder.name = NSURL.fileURL(withPath: path).lastPathComponent
            driveFolder.mimeType = FOLDER_MIME
            if parent != nil {
                driveFolder.parents = [parent!]
            }
            let query = GTLRDriveQuery_FilesCreate.query(withObject: driveFolder, uploadParameters: nil)
            query.fields = "id"
            let response = try await self.executeQueryAsync(query: query) as! GTLRDrive_File
            print("Create successful. \(path) File ID: \(response.identifier!)")

            let names = try FileManager.default.contentsOfDirectory(atPath: path)
            for name in names {
                let p = NSString.path(withComponents: [path, name])
                if isDir(p) {
                    ret.append(contentsOf: await walkDirectory(p, response.identifier!))
                } else {
                    ret.append([p, response.identifier!])
                }
            }
        } catch {
            print("walkDirectory error:", error)
        }
        return ret
    }

    func uploadFile(_ url: URL, _ parent: String?) async throws {
        let data = try Data(contentsOf: url)
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"

        let driveFile = GTLRDrive_File()
        driveFile.name = url.lastPathComponent
        driveFile.mimeType = mime
        if parent != nil {
            driveFile.parents = [parent!]
        }

        let uploadParameters = GTLRUploadParameters(data: data, mimeType: mime)
        let query = GTLRDriveQuery_FilesCreate.query(withObject: driveFile, uploadParameters: uploadParameters)
        query.fields = "id"

        let response = try await self.executeQueryAsync(query: query) as! GTLRDrive_File
        print("Upload successful. \(url.path) File ID: \(response.identifier!)\n")
    }

    @IBAction func DeleteClicked(_ sender: NSButton) {
        Task {
            if self.DRIVE_SERVICE.authorizer != nil && driveTable.numberOfSelectedRows > 0 {
                statusField.stringValue = "Deleting"

                for rowIndex in driveTable.selectedRowIndexes {
                    let row = Rows[rowIndex]
                    if row[1] != FOLDER_MIME {
                        print("del: \(row[0])")
                        let driveFile = GTLRDrive_File()
                        driveFile.trashed = true

                        let query = GTLRDriveQuery_FilesUpdate.query(withObject: driveFile, fileId: row[4], uploadParameters: nil)
                        _ = try await executeQueryAsync(query: query)
                    }
                }

                statusField.stringValue = "Done"
            } else {
                let alert = NSAlert()
                alert.messageText = "Please Login First"
                alert.alertStyle = NSAlert.Style.critical
                alert.runModal()
            }
        }
    }

    @IBAction func LogoutClicked(_ sender: NSButton) {
        GIDSignIn.sharedInstance.signOut()
        UserDefaults.standard.removeObject(forKey: "ROOT_ID")
        UserDefaults.standard.removeObject(forKey: "ROOT_QUERY")
        NSApplication.shared.windows.first!.close()
    }

    @IBAction func tableDoubleClicked(_ sender: NSTableView) {
        Task {
            if (driveTable.numberOfSelectedRows > 0) {
                let row = Rows[driveTable.selectedRow]
                if row[1] == FOLDER_MIME {
                    let id = row[4]
                    PATH.append([row[0], id])
                    pathField.stringValue = PATH.map {$0[0]!}.joined(separator: "/")

                    statusField.stringValue = "Loading"
                    try await listDirectory(id)
                    statusField.stringValue = "Done"
                }
            }
        }
    }

    func listDirectory(_ parent: String?) async throws {
        START_TIME = Date().timeIntervalSince1970
        let start_time = START_TIME
        let fileList = GTLRDriveQuery_FilesList.query()

        Rows.removeAll(keepingCapacity: true)
        if parent == nil {
            let ROOT_ID = try await getRootID()
            Rows.append([
                "My Drive",
                FOLDER_MIME,
                "",
                "",
                ROOT_ID
            ])
            driveTable.reloadData()

            statusField.stringValue = "Getting Root Query"
            fileList.q = try await getRootQuery()
            statusField.stringValue = "Loading"
        } else {
            fileList.q = "'\(parent!)' in parents"
        }
        fileList.fields = "nextPageToken, files(name, mimeType, size, owners, id, parents)"

        repeat {
            let filesResult = try await executeQueryAsync(query: fileList) as! GTLRDrive_FileList
            if START_TIME > start_time {
                break
            }

            for f in filesResult.files! {
                if parent != nil || f.parents == nil {
                    Rows.append([
                        f.name!,
                        f.mimeType!,
                        f.size != nil ? String(format: "%.2f MB", Double(truncating: f.size!) / 1024.0 / 1024.0): "",
                        (f.owners?.map({o in
                            o.displayName! + " <" + o.emailAddress! + ">"
                        }).joined(separator: "; "))!,
                        f.identifier!
                    ])
                }
            }

            let prevIndexes = driveTable.selectedRowIndexes
            driveTable.reloadData()

            // Keep selection only for subsequent pages
            if fileList.pageToken != nil {
                driveTable.selectRowIndexes(prevIndexes, byExtendingSelection: true)
            }
            rowCount.stringValue = String(Rows.count)
            fileList.pageToken = filesResult.nextPageToken
        } while (fileList.pageToken != nil)
    }

    func executeQueryAsync(query: GTLRDriveQuery) async throws -> GTLRObject {
        try await withCheckedThrowingContinuation { continuation in
            self.DRIVE_SERVICE.executeQuery(query.copy() as! GTLRDriveQuery ) { (ticket, result, error) in
                continuation.resume(with: Result<GTLRObject, Error> {
                    if error != nil {
                        throw error!
                    }
                    return result as! GTLRObject
                })
            }
        }
    }

    func initDriveService() async throws {
        if GIDSignIn.sharedInstance.hasPreviousSignIn() {
            print("Has Previous SignIn")
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            self.DRIVE_SERVICE.authorizer = user.fetcherAuthorizer
            print(user.profile!.email)
            print(user.accessToken.expirationDate!)
            print("Restore Success")
        } else {
            print("Run SignIn")
            let signInResult = try await GIDSignIn.sharedInstance.signIn(withPresenting: NSApplication.shared.windows.first!, hint: nil, additionalScopes: ["https://www.googleapis.com/auth/drive"])
            self.DRIVE_SERVICE.authorizer = signInResult.user.fetcherAuthorizer
            print("SignIn Success")
        }
    }

    func getRootID() async throws -> String {
        var ROOT_ID = UserDefaults.standard.string(forKey: "ROOT_ID")

        if ROOT_ID == nil {
            let query = GTLRDriveQuery_FilesGet.query(withFileId: "root")
            let result = try await executeQueryAsync(query: query) as! GTLRDrive_File
            ROOT_ID = result.identifier!
            UserDefaults.standard.set(ROOT_ID, forKey: "ROOT_ID")
        }

        return ROOT_ID!
    }

    func getRootQuery() async throws -> String {
        var ROOT_QUERY = UserDefaults.standard.string(forKey: "ROOT_QUERY")
        if ROOT_QUERY != nil {
            return ROOT_QUERY!
        }

        var parentList = ["root"]
        let db = ThreadSafeDictionary<String, Int>()

        await withTaskGroup(of: Void.self) { group in
            let folderList = GTLRDriveQuery_FilesList.query()
            folderList.q = "mimeType='\(FOLDER_MIME)'"
            folderList.fields = "nextPageToken, files(id)"

            repeat {
                do {
                    let foldersResult = try await executeQueryAsync(query: folderList) as! GTLRDrive_FileList
                    for f in foldersResult.files! {
                        group.addTask {
                            do {
                                try await self.countFilesInFolder(parent: f.identifier!, db: db)
                            } catch {
                                print("countFilesInFolder error:", error)
                            }
                        }
                    }

                    print("\(foldersResult.files!.count): \(String(describing: foldersResult.nextPageToken))")
                    folderList.pageToken = foldersResult.nextPageToken
                } catch {
                    print("executeQueryAsync error:", error)
                }
            } while (folderList.pageToken != nil)
        }

        let dbListKeep = db.sorted{$0.1 > $1.1}.prefix(500)

        print("dbListKeep", dbListKeep.count)
        for (key, value) in dbListKeep {
            print("\(key) -> \(value)")
        }
        parentList.append(contentsOf: dbListKeep.map{$0.key})

        ROOT_QUERY = parentList.map{"not '\($0)' in parents"}.joined(separator: " and ")
        print(ROOT_QUERY!)

        UserDefaults.standard.set(ROOT_QUERY, forKey: "ROOT_QUERY")
        return ROOT_QUERY!
    }

    func countFilesInFolder(parent: String, db: ThreadSafeDictionary<String, Int>) async throws {
        let fileList = GTLRDriveQuery_FilesList.query()
        fileList.q = "'\(parent)' in parents"
        fileList.fields = "nextPageToken, files(id)"
        var count = 0

        repeat {
            let filesResult = try await executeQueryAsync(query: fileList) as! GTLRDrive_FileList
            count += filesResult.files!.count
            fileList.pageToken = filesResult.nextPageToken
        } while (fileList.pageToken != nil)

        if count > 1 {
            db[parent] = count
        }

        print("\(parent): \(count)")
    }

    @objc func copy(_ sender: AnyObject) {
        if (driveTable.numberOfSelectedRows > 0) {
            let id = Rows[driveTable.selectedRow][4]

            let pasteBoard = NSPasteboard.general
            pasteBoard.clearContents()
            pasteBoard.setString(id, forType: .string)
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
