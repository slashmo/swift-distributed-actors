//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import DistributedActors
import DistributedActorsTestKit
import GenActors
import Foundation
import XCTest
import Files

final class GenerateActorsTests: XCTestCase {
    var system: ActorSystem!
    var testKit: ActorTestKit!

    override func setUp() {
        self.system = ActorSystem(String(describing: type(of: self)))
        self.testKit = ActorTestKit(self.system)
    }

    override func tearDown() {
        self.system.shutdown().wait()
    }

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Generator

//    func test_example() throws {
//        let gen = GenerateActors(args: [])
//
//        let folder = try Folder(path: "Tests/GenActorTests")
//        let file = try folder.file(at: "TestActorable+Actorable.swift")
//
////        try gen.run(fileToParse: file)
//    }

    // ==== ----------------------------------------------------------------------------------------------------------------
    // MARK: Generated actors

    func test_generated_TestActorable_greet() throws {
        let actor: Actor<TestActorable> = try system.spawn(.anonymous, TestActorable.init)

        actor.greet(name: "Caplin")
        actor.ref.tell(.greet(name: "Caplin"))
    }

    func test_generated_TestActorable_greet_underscoreParam() throws {
        let actor: Actor<TestActorable> = try system.spawn(.anonymous, TestActorable.init)

        actor.greetUnderscoreParam("Caplin")
        actor.ref.tell(.greetUnderscoreParam("Caplin"))
    }
}