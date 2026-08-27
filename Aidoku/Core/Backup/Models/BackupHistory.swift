//
//  BackupHistory.swift
//  Aidoku
//
//  Created by Skitty on 2/26/22.
//

import CoreData

struct BackupHistory: Codable, Hashable {
    var dateRead: Date
    var sourceId: String
    var chapterId: String
    var mangaId: String
    var progress: Int?
    var total: Int?
    var completed: Bool
    var chapterNumber: Float?
    var volumeNumber: Float?
    var chapterTitle: String?

    init(historyObject: HistoryObject) {
        dateRead = historyObject.dateRead ?? Date.distantPast
        sourceId = historyObject.sourceId
        chapterId = historyObject.chapterId
        mangaId = historyObject.mangaId
        progress = Int(historyObject.progress)
        total = Int(historyObject.total)
        completed = historyObject.completed
        chapterNumber = historyObject.chapterNumber?.floatValue
        volumeNumber = historyObject.volumeNumber?.floatValue
        chapterTitle = historyObject.chapterTitle
    }

    func toObject(context: NSManagedObjectContext) -> HistoryObject {
        let obj = HistoryObject(context: context)
        obj.dateRead = dateRead
        obj.sourceId = sourceId
        obj.chapterId = chapterId
        obj.mangaId = mangaId
        obj.progress = Int16(progress ?? -1)
        obj.total = Int16(total ?? 0)
        obj.completed = completed
        obj.chapterNumber = chapterNumber.map(NSNumber.init(value:))
        obj.volumeNumber = volumeNumber.map(NSNumber.init(value:))
        obj.chapterTitle = chapterTitle
        return obj
    }
}
