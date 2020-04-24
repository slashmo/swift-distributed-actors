//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift Distributed Actors open source project
//
// Copyright (c) 2018-2019 Apple Inc. and the Swift Distributed Actors project authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See CONTRIBUTORS.md for the list of Swift Distributed Actors project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import DistributedActorsConcurrencyHelpers
import Logging
import NIO

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: Remote Association State Machine

/// An `Association` represents a bi-directional agreement between two nodes that they are able to communicate with each other.
///
/// An association MUST be obtained with a node before any message exchange with it may occur, regardless what transport the
/// association ends up using. The association upholds the "associated only once" as well as message order delivery guarantees
/// towards the target node.
///
/// All interactions with a remote node MUST be driven through an association.
/// This is important for example if a remote node is terminated, and another node is brought up on the exact same network `Node` --
/// thus the need to keep a `UniqueNode` of both "sides" of an association -- we want to inform a remote node about our identity,
/// and want to confirm if the remote sending side of an association remains the "same exact node", or if it is a new instance on the same address.
///
/// A completed ("associated") `Association` can ONLY be obtained by successfully completing a `HandshakeStateMachine` dance,
/// as only the handshake can ensure that the other side is also an actor node that is able and willing to communicate with us.
struct Association {

    final class AssociationState: CustomStringConvertible {
        // TODO: Terrible lock which we want to get rid of; it means that every remote send has to content against all other sends about getting this ref
        // and the only reason is really because the off chance case in which we have to make an Association earlier than we have the handshake completed (i.e. we send to a ref that is not yet associated)
        let lock: Lock

        // TODO: This style of implementation queue -> channel swapping can only ever work with coarse locking and is just temporary
        //       We'd prefer to have a lock-less way to implement this and we can achieve it but it's a pain to implement so will be done in a separate step.
        var state: State

        enum State {
            case associating(queue: MPSCLinkedQueue<TransportEnvelope>)
            case associated(channel: Channel) // TODO: ActorTransport.Node/Peer/Target ???
            case tombstone(ActorRef<DeadLetter>)
        }

        /// The address of this node, that was offered to the remote side for this association
        /// This matters in case we have multiple "self" addresses; e.g. we bind to one address, but expose another because NAT
        let selfNode: UniqueNode
        var remoteNode: UniqueNode

        init(selfNode: UniqueNode, remoteNode: UniqueNode) {
            self.selfNode = selfNode
            self.remoteNode = remoteNode
            self.lock = Lock()
            self.state = .associating(queue: .init())
        }

        /// Complete the association and drain any pending message sends onto the channel.
        // TODO: This style can only ever work since we lock around the entirety of enqueueing messages and this setting; make it such that we don't need the lock eventually
        func completeAssociation(handshake: HandshakeStateMachine.CompletedState, over channel: Channel) {
            // TODO: assert that the channel is for the right remote node?

            self.lock.withLockVoid {
                switch self.state {
                case .associating(let sendQueue):
                    // 1) store associated channel
                    self.state = .associated(channel: channel)

                    // 2) we need to flush all the queued up messages
                    //    - yes, we need to flush while holding the lock... it's an annoyance in this lock based design
                    //      but it ensures that once we've flushed, all other messages will be sent in the proper order "after"
                    //      the previously enqueued ones; A lockless design would not be able to get rid of the queue AFAIR,
                    while let envelope = sendQueue.dequeue() {
                        _ = channel.writeAndFlush(envelope)
                    }

                case .associated(let existingAssociatedChannel):
                    fatalError("MUST NOT complete an association twice; Was \(existingAssociatedChannel) and tried to complete with \(channel) from \(handshake)")

                case .tombstone:
                    _ = channel.close()
                    return
                }
            }
        }

        /// Terminate the association and store a tombstone in it.
        ///
        /// If any messages were still queued up in it, or if it was hosting a channel these get drained / closed,
        /// before the tombstone is returned.
        ///
        /// After invoking this the association will never again be useful for sending messages.
        func terminate(_ system: ActorSystem) -> Association.Tombstone {
            self.lock.withLockVoid {
                switch self.state {
                case .associating(let sendQueue):
                    while let envelope = sendQueue.dequeue() {
                        system.deadLetters.tell(.init(envelope.underlyingMessage, recipient: envelope.recipient))
                    }
                    // in case someone stored a reference to this association in a ref, we swap it into a dead letter sink
                    self.state = .tombstone(system.deadLetters)
                case .associated(let channel):
                    _ = channel.close()
                    // in case someone stored a reference to this association in a ref, we swap it into a dead letter sink
                    self.state = .tombstone(system.deadLetters)
                case .tombstone:
                    () // ok
                }
            }

            return Association.Tombstone(self.remoteNode, settings: system.settings.cluster)
        }

        var description: String {
            "AssociatedState(\(self.state), selfNode: \(self.selfNode), remoteNode: \(self.remoteNode))"
        }
    }
}

extension Association.AssociationState {
    /// Concurrency: safe to invoke from any thread.
    func sendUserMessage(envelope: Envelope, recipient: ActorAddress, promise: EventLoopPromise<Void>? = nil) {
        let transportEnvelope = TransportEnvelope(envelope: envelope, recipient: recipient)
        self._send(transportEnvelope, promise: promise)
    }

    /// Concurrency: safe to invoke from any thread.
    func sendSystemMessage(_ message: _SystemMessage, recipient: ActorAddress, promise: EventLoopPromise<Void>? = nil) {
        let transportEnvelope = TransportEnvelope(systemMessage: message, recipient: recipient)
        self._send(transportEnvelope, promise: promise)
    }

    /// Concurrency: safe to invoke from any thread.
    // TODO: Reimplement association such that we don't need locks here
    private func _send(_ envelope: TransportEnvelope, promise: EventLoopPromise<Void>?) {
        self.lock.withLockVoid {
            switch self.state {
            case .associating(let sendQueue):
                sendQueue.enqueue(envelope)
            case .associated(let channel):
                channel.writeAndFlush(envelope, promise: promise)
            case .tombstone(let deadLetters):
                deadLetters.tell(.init(envelope.underlyingMessage, recipient: envelope.recipient))
            }
        }
    }
}

extension Association {
    struct Tombstone: Hashable {
        let remoteNode: UniqueNode

        /// Determines when the Tombstone should be removed from kept tombstones in the ClusterShell.
        /// End of life of the tombstone is calculated as `now + settings.associationTombstoneTTL`.
        let removalDeadline: Deadline // TODO: cluster should have timer to try to remove those periodically

        init(_ node: UniqueNode, settings: ClusterSettings) {
            // TODO: if we made system carry system.time we could always count from that point in time with a TimeAmount; require Clock and settings then
            self.removalDeadline = Deadline.fromNow(settings.associationTombstoneTTL)
            self.remoteNode = node
        }

        /// Used to create "any" tombstone, for being able to lookup in Set<TombstoneSet>
        init(_ node: UniqueNode) {
            self.removalDeadline = Deadline.uptimeNanoseconds(1) // ANY value here is ok, we do not use it in hash/equals
            self.remoteNode = node
        }

        func hash(into hasher: inout Hasher) {
            self.remoteNode.hash(into: &hasher)
        }

        static func == (lhs: Tombstone, rhs: Tombstone) -> Bool {
            lhs.remoteNode == rhs.remoteNode
        }
    }
}
