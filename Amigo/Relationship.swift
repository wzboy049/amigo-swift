//
//  Relationship.swift
//  Amigo
//
//  Created by Adam Venturella on 7/24/15.
//  Copyright © 2015 BLITZ. All rights reserved.
//

import Foundation

// there is probably a way to combine ForeignKey With relationship, they
// both are a relationship afterall. Need to think about that abstraction.

public protocol Relationship: MetaItem{
    var label: String {get}
    var type: RelationshipType {get}

}

public enum RelationshipType{
    case OneToMany, ManyToMany
}

public func ==(lhs: ManyToMany, rhs: ManyToMany) -> Bool {
    return lhs.hashValue == rhs.hashValue
}

public class ManyToMany: Relationship, CustomStringConvertible, Hashable{
    public let label: String
    public let type = RelationshipType.ManyToMany

    var left: ORMModel!
    var right: ORMModel!
    var through: ORMModel?
    let tables: [String]
    var throughModel: String?
    var associationTable: Table!

    public init(_ label: String, tables:[String], throughModel: String? = nil){
        self.label = label
        self.tables = tables.sort()
        self.throughModel = throughModel
    }

    public lazy var tableName: String = {
        return "_".join(self.tables)
    }()

    public lazy var hashValue: Int = {
        return "_".join(self.tables).hashValue
    }()

    public var description: String{
        return "<ManyToMany: \(label)>"
    }

}

public class OneToMany: Relationship, CustomStringConvertible{
    public let label: String
    public let type = RelationshipType.OneToMany

    let table: String
    let column: String

    public convenience init<T: AmigoModel>(_ label: String, using: T.Type, on: String){
        let parts = split(String(using).unicodeScalars){ $0 == "." }.map{ String($0).lowercaseString }
        let tableName = "_".join(parts)

        self.init(label, table: tableName, column: on)
    }

    public init(_ label: String, table: String, column: String){
        self.label = label
        self.table = table
        self.column = column
    }

    public var description: String{
        return "<OneToMany: \(label)>"
    }
}


//public class Relationship: MetaItem, CustomStringConvertible{
//    public let label: String
//    public let type: RelationshipType
//
//    let relatedTableLabel: String
//    let relatedColumnLabel: String
//    
//    public init(_ label: String, table: String, column: String, type: RelationshipType){
//        self.label = label
//        self.type = type
//        self.relatedTableLabel = table
//        self.relatedColumnLabel = column
//    }
//
//    public var description: String{
//        return "<Relationship: \(label)>"
//    }
//}