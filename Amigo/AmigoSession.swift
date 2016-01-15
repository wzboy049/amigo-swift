//
//  AmigoSession.swift
//  Amigo
//
//  Created by Adam Venturella on 6/29/15.
//  Copyright © 2015 BLITZ. All rights reserved.
//

import Foundation
import CoreData


public enum DatabaseAction{
    case Insert
    case Update
    case Delete
    case Unknown
}


/// Used in Many-To-Many queries
public class AmigoSessionModelAction<T: AmigoModel>{
    let using: T
    let usingModel: ORMModel
    let session: AmigoSession
    var _relationship: String?

    public init(_ obj: T, model: ORMModel, session: AmigoSession){
        self.using = obj
        self.usingModel = model
        self.session = session
    }

    public func relationship(value: String) -> AmigoSessionModelAction<T>{
        self._relationship = value
        return self
    }

    public func delete<U: AmigoModel>(other: U){

        if let key = _relationship{

            if let relationship = usingModel.relationships[key] as? ManyToMany{

                if let throughModel = relationship.throughModel{
                    fatalError("Relationship is managed though: \(throughModel)")
                }

                let leftModel = session.config.tableIndex[relationship.tables[0]]!
                let rightModel = session.config.tableIndex[relationship.tables[1]]!
                let left: AmigoModel
                let right: AmigoModel

                if leftModel == usingModel{
                    left = using
                    right = other
                } else {
                    left = other
                    right = using
                }

                let leftId = leftModel.primaryKey!.label
                let leftColumn = "\(leftModel.label)_\(leftId)"
                let leftParam = left.valueForKey(leftId)!

                let rightId = rightModel.primaryKey!.label
                let rightColumn = "\(rightModel.label)_\(rightId)"
                let rightParam = right.valueForKey(rightId)!

                var delete = relationship.associationTable.delete()

                let predicate = NSPredicate(format:" \(leftColumn) = \(leftParam) AND \(rightColumn) = \(rightParam)")

                let (filter, params) = session.engine.compiler.compile(predicate,
                    table: relationship.associationTable,
                    models: session.config.typeIndex)

                delete.filter(filter)

                let sql = session.engine.compiler.compile(delete)
                session.engine.execute(sql, params: params)
            }
        }
    }

    public func add<U: AmigoModel>(other: U...){
        add(other)
    }

    public func add<U: AmigoModel>(other: [U]){
        other.forEach(addModel)
    }

    public func addModel<U: AmigoModel>(other: U){

        if let key = _relationship{

            if let relationship = usingModel.relationships[key] as? ManyToMany{

                if let throughModel = relationship.throughModel{
                    fatalError("Relationship is managed though: \(throughModel)")
                }

                let leftModel = session.config.tableIndex[relationship.tables[0]]!
                let rightModel = session.config.tableIndex[relationship.tables[1]]!
                let left: AmigoModel
                let right: AmigoModel

                if leftModel == usingModel{
                    left = using
                    right = other
                } else {
                    left = other
                    right = using
                }

                let leftId = leftModel.primaryKey!.label
                let leftParam = left.valueForKey(leftId)!

                let rightId = rightModel.primaryKey!.label
                let rightParam = right.valueForKey(rightId)!

                let params = [leftParam, rightParam]
                let insert = relationship.associationTable.insert()
                let sql = session.engine.compiler.compile(insert)
                
                session.engine.execute(sql, params: params)
            }
        }
    }
}

public class AmigoSession: AmigoConfigured{
    public let config: AmigoConfiguration

    public init(config: AmigoConfiguration){
        self.config = config
    }

    public func begin(){
        config.engine.beginTransaction()
    }

    public func rollback(){
        config.engine.rollback()
    }

    public func commit(){
        config.engine.commitTransaction()
        begin()
    }

    public func batch(handler: (BatchOperation) -> ()) {
        let operation = engine.createBatchOperation(self)
        handler(operation)
        operation.execute()
    }

    public func query<T: AmigoModel>(value: T.Type) -> QuerySet<T>{
        let type = value.description()
        let model = typeIndex[type]!
        return QuerySet<T>(model: model, config: config)
    }

    public func using<U: AmigoModel>(obj: U) -> AmigoSessionModelAction<U>{
        let type = U.description()
        let model = config.typeIndex[type]!
        let action = AmigoSessionModelAction(obj, model: model, session: self)

        return action
    }

    public func add<T: AmigoModel>(obj: T, upsert: Bool = false){
        add([obj], upsert: upsert)
    }

    public func delete<T: AmigoModel>(obj: T){
        delete([obj])
    }

    public func add<T: AmigoModel>(objs: [T], upsert: Bool = false){
        objs.forEach{ self.addModel($0, upsert: upsert) }
    }

    public func delete<T: AmigoModel>(objs: [T]){
        objs.forEach(self.deleteModel)
    }

    public func addAction<T: AmigoModel>(obj: T) -> DatabaseAction{
        let model = obj.amigoModel
        let primaryKeyValue = model.primaryKey.modelValue(obj)

        switch model.primaryKey.type{
        case .Integer16AttributeType: fallthrough
        case .Integer32AttributeType: fallthrough
        case .Integer64AttributeType:
            if primaryKeyValue == nil{
                return .Insert
            } else if let primaryKeyValue = primaryKeyValue as? Int where primaryKeyValue == 0 {
                return .Insert
            }
        default:
            if primaryKeyValue == nil{
                return .Insert
            }
        }

        return .Update
    }

    public func addModel<T: AmigoModel>(obj: T, upsert isUpsert: Bool = false){
        let model = obj.amigoModel
        let action: DatabaseAction

        if isUpsert{
            upsert(obj, model: model)
            return
        }

        action = addAction(obj)

        let method = (action == .Insert) ? insert : update
        method(obj, model: model)
    }


    public func upsertSQL(model: ORMModel) -> String{
        if let sql = model.sqlUpsert{
            return sql
        }

        let insert = model.table.insert(upsert: true)
        let sql = engine.compiler.compile(insert)
        model.sqlUpsert = sql

        return sql
    }

    public func insertSQL(model: ORMModel) -> String{
        if let sql = model.sqlInsert{
            return sql
        }

        let insert = model.table.insert()
        let sql = engine.compiler.compile(insert)
        model.sqlInsert = sql

        return sql
    }

    
    public func updateSQL<T: AmigoModel>(obj: T) -> (String, [AnyObject]){
        let model = obj.amigoModel
        let id = model.primaryKey.label
        let value = obj.valueForKey(id)!


        let sql: String
        let predicateParams: [AnyObject]

        if let cachedSql = model.sqlUpdate{
            sql = cachedSql
            predicateParams = [model.primaryKey.modelValue(obj)!]

        } else {
            var update = model.table.update()
            let predicate = NSPredicate(format: "\(id) = '\(value)'")
            let (filter, params) = engine.compiler.compile(predicate, table: model.table, models: config.tableIndex)

            update.filter(filter)
            sql = engine.compiler.compile(update)
            predicateParams = params

            model.sqlUpdate = sql
        }

        return (sql, predicateParams)
    }

    public func deleteSQL<T: AmigoModel>(obj: T) -> (String, [AnyObject]){
        let model = obj.amigoModel
        let id = model.primaryKey.label
        let value = obj.valueForKey(id)!

        let sql: String
        let predicateParams: [AnyObject]

        if let cachedSql = model.sqlDelete{
            sql = cachedSql
            predicateParams = [model.primaryKey.modelValue(obj)!]

        } else {
            var delete = model.table.delete()
            let predicate = NSPredicate(format: "\(id) = '\(value)'")
            let (filter, params) = engine.compiler.compile(predicate, table: model.table, models: config.tableIndex)

            delete.filter(filter)
            sql = engine.compiler.compile(delete)
            predicateParams = params

            model.sqlDelete = sql
        }

        return (sql, predicateParams)
    }

    public func deleteThroughModelSQL<T: AmigoModel>(obj: T, relationship: ManyToMany, value: AnyObject) -> (String, [AnyObject]) {

        let model = obj.amigoModel
        let throughModel = relationship.through!
        let throughId = "\(throughModel.label)_\(throughModel.primaryKey!.label)"

        let sql: String
        let predicateParams: [AnyObject]
        let cacheKey = relationship.associationTable.label

        if let cachedSql = model.sqlDeleteThrough[cacheKey]{
            sql = cachedSql
            predicateParams = [value]

        } else {
            var delete = relationship.associationTable.delete()
            let predicate = NSPredicate(format: "\(throughId) = \(value)")
            let (filter, params) = engine.compiler.compile(predicate, table: relationship.associationTable, models: config.tableIndex)

            delete.filter(filter)
            sql = engine.compiler.compile(delete)
            predicateParams = params

            model.sqlDeleteThrough[cacheKey] = sql
        }

        return (sql, predicateParams)
    }

    public func insertParams<T: AmigoModel>(obj: T, upsert isUpsert: Bool = false) -> SQLParams{
        let model = obj.amigoModel
        var automaticPrimaryKey = false
        var params = [AnyObject]()
        var defaults = [String: AnyObject]()

        model.table.sortedColumns.forEach{
            var value: AnyObject?
            let null = NSNull()


            if $0.primaryKey && $0.type == .Integer64AttributeType{
                automaticPrimaryKey = true

                if isUpsert == false {
                    return
                }
            }

            if let column = $0.foreignKey{
                let parts = $0.label.unicodeScalars.split{ $0 == "_"}.map(String.init)

                if let target = obj.valueForKey(parts[0]) as? AmigoModel{
                    let fkModel = config.tableIndex[column.relatedColumn.table!.label]!

                    if let id = fkModel.primaryKey.modelValue(target) {
                        value = id
                    } else {

                        if isUpsert{
                            self.upsert(target, model: fkModel)
                        } else {
                            self.insert(target, model: fkModel)
                        }

                        value = fkModel.primaryKey.modelValue(target)
                    }
                } else {
                    value = null
                }
            } else {
                value = null
                let currentValue = $0.modelValue(obj)
                let candidateValue = $0.valueOrDefault(currentValue)

                if currentValue == nil && candidateValue != nil{
                    defaults[$0.label] = candidateValue
                }

                if let serializedValue = $0.serialize(candidateValue){
                    value = serializedValue
                } else {
                    value = null
                }
            }
            
            params.append(value!)
        }

        let sqlParams = SQLParams(
            queryParams: params,
            defaultValues: defaults,
            automaticPrimaryKey: automaticPrimaryKey
        )

        return sqlParams
    }

    public func insertManyToManyThroughModel<T: AmigoModel>(obj: T, model: ORMModel, upsert: Bool = false){
        if let relationship = model.throughModelRelationship{
            let left = relationship.left
            let right = relationship.right

            var leftKey: String!
            var rightKey: String!

            model.foreignKeys.forEach{ (key: String, c: Column) -> Void in

                let fk = c.foreignKey!
                if fk.relatedColumn == relationship.left.primaryKey{
                    leftKey = key
                }

                if fk.relatedColumn == relationship.right.primaryKey{
                    rightKey = key
                }
            }

            let leftParam = obj.valueForKeyPath("\(leftKey).\(left.primaryKey!.label)")!
            let rightParam = obj.valueForKeyPath("\(rightKey).\(right.primaryKey!.label)")!
            let throughParam = obj.valueForKey("\(model.primaryKey.label)")!

            let params = [leftParam, rightParam, throughParam]
            let insert = relationship.associationTable.insert(upsert: upsert)
            let sql = engine.compiler.compile(insert)
            
            engine.execute(sql, params: params)
        }
    }

    func upsert<T: AmigoModel>(obj: T, model: ORMModel){
        let sql = upsertSQL(model)
        let params = insertParams(obj, upsert: true)

        engine.execute(sql, params: params.queryParams)

        if params.automaticPrimaryKey && model.primaryKey.modelValue(obj) == nil{
            let id = self.engine.lastrowid()
            obj.setValue(id, forKey: model.primaryKey.label)
        }

        // push any defaults back to the model only AFTER
        // we have executed the query
        params.defaultValues.forEach{ key, value in
            obj.setValue(value, forKey: key)
        }

        self.insertManyToManyThroughModel(obj, model: model, upsert: true)
    }

    func insert<T: AmigoModel>(obj: T, model: ORMModel){
        let sql = insertSQL(model)
        let params = insertParams(obj)

        engine.execute(sql, params: params.queryParams)

        if params.automaticPrimaryKey && engine.fetchLastRowIdAfterInsert{
            let id = self.engine.lastrowid()
            obj.setValue(id, forKey: model.primaryKey.label)
        }

        // push any defaults back to the model only AFTER
        // we have executed the query
        params.defaultValues.forEach{ key, value in
            obj.setValue(value, forKey: key)
        }

        self.insertManyToManyThroughModel(obj, model: model)
    }

    func update<T: AmigoModel>(obj: T, model: ORMModel){
        let(sql, predicateParams) = updateSQL(obj)
        let params = insertParams(obj)

        engine.execute(sql, params: (params.queryParams + predicateParams))

        // push any defaults back to the model only AFTER
        // we have executed the query
        params.defaultValues.forEach{ key, value in
            obj.setValue(value, forKey: key)
        }
    }

    public func deleteModel<T: AmigoModel>(obj: T){
        let(sql, predicateParams) = deleteSQL(obj)
        engine.execute(sql, params: predicateParams)

        deleteThroughModelRelationship(obj)
    }

    public func deleteThroughModelRelationship<T: AmigoModel>(obj: T){
        let model = obj.amigoModel
        let value = model.primaryKey.modelValue(obj)

        if let relationship = model.throughModelRelationship, let value = value {

            let (sql, predicateParams) = deleteThroughModelSQL(obj, relationship: relationship, value: value)
            engine.execute(sql, params: predicateParams)
        }
    }
}
