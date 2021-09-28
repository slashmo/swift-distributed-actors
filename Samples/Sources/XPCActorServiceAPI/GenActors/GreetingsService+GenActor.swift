// ==== ------------------------------------------------------------------ ====
// === DO NOT EDIT: Generated by GenActors                     
// ==== ------------------------------------------------------------------ ====


// tag::xpc_example[]
import DistributedActors
import DistributedActorsXPC
import NIO

// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: DO NOT EDIT: Generated GreetingsService messages 

extension GeneratedActor.Messages {
    public enum GreetingsService: ActorMessage { 
        case logGreeting(name: String) 
        case greet(name: String, _replyTo: ActorRef<Result<String, ErrorEnvelope>>) 
        case fatalCrash 
        case greetDirect(who: ActorRef<String>) 
        case greetFuture(name: String, _replyTo: ActorRef<Result<String, ErrorEnvelope>>)  
    }
}
// ==== ----------------------------------------------------------------------------------------------------------------
// MARK: DO NOT EDIT: Boxing GreetingsService for any inheriting actorable `A` 

extension Actor where Act: GreetingsService {

    public func logGreeting(name: String) {
        self.ref.tell(Act._boxGreetingsService(.logGreeting(name: name)))
    }
 

    public func greet(name: String) -> Reply<String> {
        // TODO: FIXME perhaps timeout should be taken from context
        Reply.from(askResponse: 
            self.ref.ask(for: Result<String, ErrorEnvelope>.self, timeout: .effectivelyInfinite) { _replyTo in
                Act._boxGreetingsService(.greet(name: name, _replyTo: _replyTo))
            }
        )
    }
 

    public func fatalCrash() {
        self.ref.tell(Act._boxGreetingsService(.fatalCrash))
    }
 

    public func greetDirect(who: ActorRef<String>) {
        self.ref.tell(Act._boxGreetingsService(.greetDirect(who: who)))
    }
 

    public func greetFuture(name: String) -> Reply<String> {
        // TODO: FIXME perhaps timeout should be taken from context
        Reply.from(askResponse: 
            self.ref.ask(for: Result<String, ErrorEnvelope>.self, timeout: .effectivelyInfinite) { _replyTo in
                Act._boxGreetingsService(.greetFuture(name: name, _replyTo: _replyTo))
            }
        )
    }
 

}