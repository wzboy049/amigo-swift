//
//  ORMModel.swift
//  Amigo
//
//  Created by Adam Venturella on 7/12/15.
//  Copyright © 2015 BLITZ. All rights reserved.
//

import Foundation

public func ==(lhs: ORMModel, rhs: ORMModel) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

public class ORMModel: Hashable{
    public static let metadata = MetaData()

    public let table: Table
    public let foreignKeys: [String:Column]
    public let relationships: [String:Relationship]
    public let columns: [Column]
    public let primaryKey: Column!
    public let type: String
    public let label: String
    public var throughModelRelationship: ManyToMany?

    public convenience init<T:AmigoModel>(_ qualifiedType: T.Type, _ properties: MetaItem...){
        let qualifiedType = String(qualifiedType)
        self.init(qualifiedType, properties: properties)
    }

    public convenience init(_ qualifiedType: String, properties: MetaItem...){
        self.init(qualifiedType, properties: properties)
    }

    public init(_ qualifiedType: String, properties:[MetaItem]){
        let schemaItems = properties.filter{$0 is SchemaItem}.map{ $0 as! SchemaItem}
        let relationshipList = properties.filter{$0 is Relationship}.map{ $0 as! Relationship }
        let nameParts = split(qualifiedType.unicodeScalars)
                       { $0 == "." }
                       .map{ String($0).lowercaseString }

        let tableName = "_".join(nameParts)
        var tmpForeignKeys = [String:Column]()
        var tmpColumns = [Column]()
        var tmpPrimaryKey: Column!
        var tmpRelationships = [String: Relationship]()

        type = qualifiedType
        label = nameParts[1]
        table = Table(tableName, metadata: ORMModel.metadata, items: schemaItems)

        relationshipList.map{tmpRelationships[$0.label] = $0}

        table.sortedColumns.map{ value -> () in
            if value.foreignKey != nil{
                // foreign keys will have column names like:
                // `foo_id`, but the relationship will be something
                // like `foo` for selectRelated in the QuerySet,
                // so we strip off the _id
                let parts = split(value.label.characters){ $0 == "_" }
                    .map(String.init)

                tmpForeignKeys[parts[0]] = value
            } else {
                tmpColumns.append(value)
                if value.primaryKey {
                    tmpPrimaryKey = value
                }
            }
        }

        foreignKeys = tmpForeignKeys
        columns = tmpColumns
        primaryKey = tmpPrimaryKey
        relationships = tmpRelationships
    }

    public var hashValue: Int{
        return type.hashValue
    }
}