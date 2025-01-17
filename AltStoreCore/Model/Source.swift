//
//  Source.swift
//  AltStore
//
//  Created by Riley Testut on 7/30/19.
//  Copyright © 2019 Riley Testut. All rights reserved.
//

import CoreData
import UIKit

public extension Source
{
    #if ALPHA
    static let altStoreIdentifier = "com.rileytestut.AltStore.Alpha"
    #else
    static let altStoreIdentifier = "com.rileytestut.AltStore"
    #endif
    
    #if STAGING
    
    #if ALPHA
    static let altStoreSourceURL = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/sources/alpha/apps-alpha-staging.json")!
    #else
    static let altStoreSourceURL = URL(string: "https://f000.backblazeb2.com/file/altstore-staging/apps-staging.json")!
    #endif
    
    #else
    
    #if ALPHA
    static let altStoreSourceURL = URL(string: "https://alpha.altstore.io/")!
    #else
    static let altStoreSourceURL = URL(string: "https://apps.altstore.io/")!
    #endif
    
    #endif
}

public extension Source
{
    // Fallbacks for optional JSON values.
    
    var effectiveIconURL: URL? {
        return self.iconURL ?? self.apps.first?.iconURL
    }
    
    var effectiveHeaderImageURL: URL? {
        return self.headerImageURL ?? self.effectiveIconURL
    }
    
    var effectiveTintColor: UIColor? {
        return self.tintColor ?? self.apps.first?.tintColor
    }
    
    var effectiveFeaturedApps: [StoreApp] {
        return self.featuredApps ?? self.apps
    }
}

@objc(Source)
public class Source: NSManagedObject, Fetchable, Decodable
{
    /* Properties */
    @NSManaged public var name: String
    @NSManaged public var identifier: String
    @NSManaged public var sourceURL: URL
    
    /* Source Detail */
    @NSManaged public var subtitle: String?
    @NSManaged public var websiteURL: URL?
    @NSManaged public var localizedDescription: String?
    
    // Optional properties with fallbacks.
    // `private` to prevent accidentally using instead of `effective[PropertyName]`
    @NSManaged private var iconURL: URL?
    @NSManaged private var headerImageURL: URL?
    @NSManaged private var tintColor: UIColor?
    
    @NSManaged public var error: NSError?
    
    /* Non-Core Data Properties */
    public var userInfo: [ALTSourceUserInfoKey: String]?
    
    /* Relationships */
    @objc(apps) @NSManaged public private(set) var _apps: NSOrderedSet
    @objc(newsItems) @NSManaged public private(set) var _newsItems: NSOrderedSet
    
    @objc(featuredApps) @NSManaged public private(set) var _featuredApps: NSOrderedSet
    @objc(hasFeaturedApps) @NSManaged private var _hasFeaturedApps: Bool
    
    @nonobjc public var apps: [StoreApp] {
        get {
            return self._apps.array as! [StoreApp]
        }
        set {
            self._apps = NSOrderedSet(array: newValue)
        }
    }
    
    @nonobjc public var newsItems: [NewsItem] {
        get {
            return self._newsItems.array as! [NewsItem]
        }
        set {
            self._newsItems = NSOrderedSet(array: newValue)
        }
    }
    
    // `internal` to prevent accidentally using instead of `effectiveFeaturedApps`
    @nonobjc internal var featuredApps: [StoreApp]? {
        return self._hasFeaturedApps ? self._featuredApps.array as? [StoreApp] : nil
    }
    
    private enum CodingKeys: String, CodingKey
    {
        case name
        case identifier
        case sourceURL
        case subtitle
        case localizedDescription = "description"
        case iconURL
        case headerImageURL = "headerURL"
        case websiteURL = "website"
        case tintColor
        
        case apps
        case news
        case featuredApps
        case userInfo
    }
    
    private override init(entity: NSEntityDescription, insertInto context: NSManagedObjectContext?)
    {
        super.init(entity: entity, insertInto: context)
    }
    
    public required init(from decoder: Decoder) throws
    {
        guard let context = decoder.managedObjectContext else { preconditionFailure("Decoder must have non-nil NSManagedObjectContext.") }
        guard let sourceURL = decoder.sourceURL else { preconditionFailure("Decoder must have non-nil sourceURL.") }
        
        super.init(entity: Source.entity(), insertInto: context)
        
        do
        {
            self.sourceURL = sourceURL
            
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try container.decode(String.self, forKey: .name)
            self.identifier = try container.decode(String.self, forKey: .identifier)
            
            // Optional Values
            self.subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle)
            self.websiteURL = try container.decodeIfPresent(URL.self, forKey: .websiteURL)
            self.localizedDescription = try container.decodeIfPresent(String.self, forKey: .localizedDescription)
            self.iconURL = try container.decodeIfPresent(URL.self, forKey: .iconURL)
            self.headerImageURL = try container.decodeIfPresent(URL.self, forKey: .headerImageURL)
            
            if let tintColorHex = try container.decodeIfPresent(String.self, forKey: .tintColor)
            {
                guard let tintColor = UIColor(hexString: tintColorHex) else {
                    throw DecodingError.dataCorruptedError(forKey: .tintColor, in: container, debugDescription: "Hex code is invalid.")
                }
                
                self.tintColor = tintColor
            }
            
            let userInfo = try container.decodeIfPresent([String: String].self, forKey: .userInfo)
            self.userInfo = userInfo?.reduce(into: [:]) { $0[ALTSourceUserInfoKey($1.key)] = $1.value }
            
            let apps = try container.decodeIfPresent([StoreApp].self, forKey: .apps) ?? []
            let appsByID = Dictionary(apps.map { ($0.bundleIdentifier, $0) }, uniquingKeysWith: { (a, b) in return a })
            
            for (index, app) in apps.enumerated()
            {
                app.sourceIdentifier = self.identifier
                app.sortIndex = Int32(index)
            }
            self._apps = NSMutableOrderedSet(array: apps)
            
            let newsItems = try container.decodeIfPresent([NewsItem].self, forKey: .news) ?? []
            for (index, item) in newsItems.enumerated()
            {
                item.sourceIdentifier = self.identifier
                item.sortIndex = Int32(index)
            }
                                
            for newsItem in newsItems
            {
                guard let appID = newsItem.appID else { continue }
                
                if let storeApp = appsByID[appID]
                {
                    newsItem.storeApp = storeApp
                }
                else
                {
                    newsItem.storeApp = nil
                }
            }
            self._newsItems = NSMutableOrderedSet(array: newsItems)
            
            let featuredAppBundleIDs = try container.decodeIfPresent([String].self, forKey: .featuredApps)
            let featuredApps = featuredAppBundleIDs?.compactMap { appsByID[$0] }
            self.setFeaturedApps(featuredApps)
        }
        catch
        {
            if let context = self.managedObjectContext
            {
                context.delete(self)
            }
            
            throw error
        }
    }
}

public extension Source
{
    // Source is considered added IFF it has been saved to disk,
    // which we can check by fetching on a new managed object context.
    var isAdded: Bool {
        get async throws {
            let identifier = await AsyncManaged(wrappedValue: self).identifier
            let backgroundContext = DatabaseManager.shared.persistentContainer.newBackgroundContext()
            
            let isAdded = try await backgroundContext.performAsync {
                let fetchRequest = Source.fetchRequest()
                fetchRequest.predicate = NSPredicate(format: "%K == %@", #keyPath(Source.identifier), identifier)
                
                let count = try backgroundContext.count(for: fetchRequest)
                return (count > 0)
            }
            
            return isAdded
        }
    }
}

internal extension Source
{
    func setFeaturedApps(_ featuredApps: [StoreApp]?)
    {
        // Explicitly update relationships for all apps to ensure featuredApps merges correctly.
        
        for case let storeApp as StoreApp in self._apps
        {
            if let featuredApps, featuredApps.contains(where: { $0.bundleIdentifier == storeApp.bundleIdentifier })
            {
                storeApp.featuringSource = self
            }
            else
            {
                storeApp.featuringSource = nil
            }
        }
        
        self._featuredApps = NSOrderedSet(array: featuredApps ?? [])
        self._hasFeaturedApps = (featuredApps != nil)
    }
}

public extension Source
{
    @nonobjc class func fetchRequest() -> NSFetchRequest<Source>
    {
        return NSFetchRequest<Source>(entityName: "Source")
    }
    
    class func makeAltStoreSource(in context: NSManagedObjectContext) -> Source
    {
        let source = Source(context: context)
        source.name = "AltStore"
        source.identifier = Source.altStoreIdentifier
        source.sourceURL = Source.altStoreSourceURL
        
        return source
    }
    
    class func fetchAltStoreSource(in context: NSManagedObjectContext) -> Source?
    {
        let source = Source.first(satisfying: NSPredicate(format: "%K == %@", #keyPath(Source.identifier), Source.altStoreIdentifier), in: context)
        return source
    }
}
