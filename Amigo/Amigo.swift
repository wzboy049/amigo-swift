//
//  Amigo.swift
//  Amigo
//
//  Created by Adam Venturella on 6/29/15.
//  Copyright © 2015 BLITZ. All rights reserved.
//

import Foundation
import CoreData


public class Amigo: AmigoConfigured{

    public let config: AmigoConfiguration
    public let engineFactory: EngineFactory

    public func query<T: AmigoModel>(value: T.Type) -> QuerySet<T>{
        //let tableName = mapper.dottedNameToTableName(String(value))
        let model = typeIndex[String(value)]!
        return QuerySet<T>(model: model, config: threadConfig())
    }

    public var session: AmigoSession{
        // there is currently an issue here with multiple threads.
        // a session could be grabbed from each thread, but in the current
        // model they are effectively using the same connection.
        // there will be many unintended consequences.
        // 
        // it may be best here to use a new connection per session
        // we would need to ensure sqlite is compiled in multi-threaded mode:
        // https://www.sqlite.org/threadsafe.html
        // 
        // for now lets just get things working so we are ignoring it.
        // in the case of FMDB, per the docs it's always been safe to make
        // a FMDatabase object per thread.


        let session =  AmigoSession(config: threadConfig())
        session.begin()
        return session
    }

    public convenience init(_ mom: NSManagedObjectModel, factory: EngineFactory, mapperType: AmigoEntityDescriptionMapper.Type = EntityDescriptionMapper.self){
        let mapper = mapperType.init()
        let models = mom.sortedEntities().map(mapper.map)
        self.init(models, factory: factory, mapper: mapper)
    }

    public convenience init(_ models: [ORMModel], factory: EngineFactory, mapperType: Mapper.Type = DefaultMapper.self){
        let mapper = mapperType.init()
        self.init(models, factory: factory, mapper: mapper)
    }

    public init(_ models: [ORMModel], factory: EngineFactory, mapper: Mapper){
        var tableIndex = [String:ORMModel]()
        var typeIndex = [String:ORMModel]()

        models.map{ model -> () in
            tableIndex[model.table.label] = model
            typeIndex[model.type] = model
        }

        engineFactory = factory

        self.config = AmigoConfiguration(
            engine: factory.connect(),
            mapper: mapper,
            tableIndex: tableIndex,
            typeIndex: typeIndex
        )

        initializeManyToMany(models)
    }

    func initializeManyToMany(models:[ORMModel]){
        // find all the ManyToMany Relationships so we can inject tables.
        let relationships = models
            .map{$0.relationships.values.array}
            .flatMap{$0}

        let m2m = relationships.filter{$0 is ManyToMany}.map{$0 as! ManyToMany}
        var m2mHash = [ManyToMany: [ManyToMany]]()
        var m2mThroughModels = [ManyToMany]()

        m2m.map{ (value: ManyToMany) -> Void in
            value.left = config.tableIndex[value.tables[0]]!
            value.right = config.tableIndex[value.tables[1]]!

            if var container = m2mHash[value]{
                container.append(value)
                m2mHash[value] = container
            } else {
                let container = [value]
                m2mHash[value] = container
            }

            if let throughModel = value.throughModel{
                let model = config.typeIndex[throughModel]!

                model.throughModelRelationship = value
                value.through = model

                model.foreignKeys.values.array.map{ (c: Column) -> Void in
                    if c.foreignKey!.relatedColumn == value.left.primaryKey || c.foreignKey!.relatedColumn == value.right.primaryKey{
                        c.optional = false
                    }
                }

                m2mThroughModels.append(value)
            }
        }

        // ensure the throughModel is registered on both
        // sides of the relationship
        m2mThroughModels.map{ (value: ManyToMany) -> Void in
            m2mHash[value]?.map{ (each: ManyToMany) -> Void in
                each.throughModel = value.throughModel
                each.through = value.through
            }
        }

        // use the set to omit duplicates
        Set(m2m).map{ (value: ManyToMany) -> Void in
            let left = "\(value.left.label)_\(value.left.primaryKey!.label)"
            let right = "\(value.right.label)_\(value.right.primaryKey!.label)"

            var columns: [SchemaItem] = [
                Column("id", type: Int.self, primaryKey: true),
                Column(left, type: ForeignKey(value.left.table), indexed: true, optional: false),
                Column(right, type: ForeignKey(value.right.table), indexed: true, optional: false)
            ]

            if let model = value.through{
                let label = "\(model.label)_\(model.primaryKey!.label)"
                columns.append(Column(label, type: ForeignKey(model.table), indexed: true, optional: false))
            }

            let table = Table(value.tableName, metadata: ORMModel.metadata, items: columns)

            m2mHash[value]?.map{ (value: ManyToMany) -> Void in
                print(value.label)
                value.associationTable = table
            }
        }
    }

    func threadConfig() -> AmigoConfiguration{
        let obj = AmigoConfiguration(
            engine: engineFactory.connect(),
            mapper: config.mapper,
            tableIndex: config.tableIndex,
            typeIndex: config.typeIndex
        )

        return obj
    }

    public func execute(sql: String, params: [AnyObject]! = nil){
        config.engine.execute(sql, params: params)
    }

    public func execute<Input, Output>(sql: String, params: [AnyObject]! = nil, mapper: Input -> Output) -> Output {
        return config.engine.execute(sql, params: params, mapper: mapper)
    }

    public func createAll(){
        ORMModel.metadata.createAll(config.engine)
    }


}