import Foundation

enum Storage {
    static let groupID = "group.com.beauregardhenry.makingroceries"
    static let fileNames = ["grocery", "shops", "favorites", "meals", "history", "recurring", "plan", "stock", "spending"]

    /// The app group container when there is one, so widgets and Siri see the same data;
    /// otherwise Documents. Files from earlier versions are copied across once.
    /// UI tests launch the app with this argument to start from fresh sample data, apart from real data.
    static let isUITesting = ProcessInfo.processInfo.arguments.contains("-ui-testing")

    static let directory: URL = {
        if isUITesting {
            let folder = FileManager.default.temporaryDirectory.appending(path: "ui-testing", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let docs = URL.documentsDirectory
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            return docs
        }
        for name in fileNames {
            let old = docs.appending(path: "\(name).json")
            let new = group.appending(path: "\(name).json")
            if FileManager.default.fileExists(atPath: old.path), !FileManager.default.fileExists(atPath: new.path) {
                try? FileManager.default.copyItem(at: old, to: new)
            }
        }
        return group
    }()

    static func url(_ name: String) -> URL { directory.appending(path: "\(name).json") }

    static var photos: URL {
        let url = directory.appending(path: "photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
