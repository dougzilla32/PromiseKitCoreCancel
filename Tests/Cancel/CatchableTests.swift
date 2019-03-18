import PromiseKit
import Dispatch
import XCTest

class CatchableTests: XCTestCase {

    func testFinally() {
        let finallyQueue = DispatchQueue(label: "\(#file):\(#line)", attributes: .concurrent)

        func helper(error: Error, on queue: DispatchQueue = .main, flags: DispatchWorkItemFlags? = nil) {
            let ex = (expectation(description: ""), expectation(description: ""))
            var x = 0
            let p = after(seconds: 0.01).cancellize().catch(policy: .allErrors) { _ in
                XCTAssertEqual(x, 0)
                x += 1
                ex.0.fulfill()
            }.finally(on: queue, flags: flags) {
                if let flags = flags, flags.contains(.barrier) {
                    dispatchPrecondition(condition: .onQueueAsBarrier(queue))
                } else {
                    dispatchPrecondition(condition: .onQueue(queue))
                }
                XCTAssertEqual(x, 1)
                x += 1
                ex.1.fulfill()
            }

            p.cancel(with: error)

            wait(for: [ex.0, ex.1], timeout: 10)
        }

        helper(error: Error.dummy)
        helper(error: Error.cancelled)
        helper(error: Error.dummy, on: finallyQueue)
        helper(error: Error.dummy, on: finallyQueue, flags: .barrier)
    }

    func testCauterize() {
        let ex = expectation(description: "")
        let p = after(seconds: 0.01).cancellize()

        // cannot test specifically that this outputs to console,
        // but code-coverage will note that the line is run
        p.cauterize()

        p.catch { _ in
            ex.fulfill()
        }

        p.cancel(with: Error.dummy)

        wait(for: [ex], timeout: 1)
    }
}

/// `Promise<Void>.recover`
extension CatchableTests {
    func test__void_specialized_full_recover() {

        func helper(policy: CatchPolicy, error: Swift.Error, line: UInt = #line) {
            let ex = expectation(description: "error caught")
            CancellablePromise(error: error).recover { _ in }.done { _ in XCTFail() }.catch(policy: .allErrors, ex.fulfill).cancel()
            wait(for: [ex], timeout: 1)
        }

        helper(policy: .allErrorsExceptCancellation, error: Error.dummy)
        helper(policy: .allErrors, error: Error.dummy)
        helper(policy: .allErrorsExceptCancellation, error: Error.cancelled)
        helper(policy: .allErrors, error: Error.cancelled)

        let ex2 = expectation(description: "cancel caught")
        let d2 = CancellablePromise(error: Error.cancelled).recover(policy: .allErrors) { _ in }.done(ex2.fulfill)
        d2.cancel()
        wait(for: [ex2], timeout: 1)
    }

    func test__void_specialized_full_recover__fulfilled_path() {
        let ex = expectation(description: "")
        CancellablePromise().recover { _ in
            XCTFail()
        }.done { _ in
            XCTFail()
        }.catch(policy: .allErrors) {
            $0.isCancelled ? ex.fulfill() : XCTFail()
        }.cancel()
        wait(for: [ex], timeout: 1)

        let ex2 = expectation(description: "")
        let promise = CancellablePromise()
        promise.cancel()
        promise.recover(policy: .allErrors) { _ in }.done(ex2.fulfill).catch(policy: .allErrors) { _ in XCTFail() }
        wait(for: [ex2], timeout: 1)
    }

    func test__void_specialized_conditional_recover() {
        func helperDone(policy: CatchPolicy, error: Swift.Error, line: UInt = #line) {
            let ex = expectation(description: "")
            var x = 0
            let promise = CancellablePromise(error: error).recover(policy: policy) { (err: Swift.Error) throws -> Void in
                guard x < 1 else { throw err }
                x += 1
            }.done(ex.fulfill).catch(policy: .allErrors) { _ in
                XCTFail()
            }
            promise.cancel()
            wait(for: [ex], timeout: 1)
        }

        func helperCatch(policy: CatchPolicy, error: Swift.Error, line: UInt = #line) {
            let ex = expectation(description: "")
            var x = 0
            let promise = CancellablePromise(error: error).recover(policy: policy) { (err: Swift.Error) throws -> Void in
                guard x < 1 else { throw err }
                x += 1
            }.done { _ in
                XCTFail()
            }.catch(policy: .allErrors) {
                $0.isCancelled ? ex.fulfill() : XCTFail()
            }
            promise.cancel()
            wait(for: [ex], timeout: 1)
        }

        for error in [Error.dummy as Swift.Error, Error.cancelled] {
            helperDone(policy: .allErrors, error: error)
        }
        helperCatch(policy: .allErrorsExceptCancellation, error: Error.dummy)
    }

    func test__void_specialized_conditional_recover__no_recover() {

        func helper(policy: CatchPolicy, error: Error, line: UInt = #line) {
            let ex = expectation(description: "")
            CancellablePromise(error: error).recover(policy: .allErrorsExceptCancellation) { err in
                throw err
            }.catch(policy: .allErrors) { _ in
                ex.fulfill()
            }.cancel()
            wait(for: [ex], timeout: 1)
        }

        for error in [Error.dummy, Error.cancelled] {
            helper(policy: .allErrors, error: error)
        }
        helper(policy: .allErrorsExceptCancellation, error: Error.dummy)
    }

    func test__void_specialized_conditional_recover__ignores_cancellation_but_fed_cancellation() {
        let ex = expectation(description: "")
        CancellablePromise(error: Error.cancelled).recover(policy: .allErrorsExceptCancellation) { _ in
            XCTFail()
        }.catch(policy: .allErrors) {
            XCTAssertEqual(Error.cancelled, $0 as? Error)
            ex.fulfill()
        }.cancel()
        wait(for: [ex], timeout: 1)
    }

    func test__void_specialized_conditional_recover__fulfilled_path() {
        let ex = expectation(description: "")
        let p = CancellablePromise().recover { _ in
            XCTFail()
        }.catch { _ in
            XCTFail()   // this `catch` to ensure we are calling the `recover` variant we think we are
        }.finally {
            ex.fulfill()
        }
        p.cancel()
        wait(for: [ex], timeout: 1)
    }
}

/// `Promise<T>.recover`
extension CatchableTests {
    func test__full_recover() {
        func helper(error: Swift.Error) {
            let ex = expectation(description: "")
            CancellablePromise<Int>(error: error).recover { _ in
                return Promise.value(2).cancellize()
            }.done { _ in
                XCTFail()
            }.catch(policy: .allErrors, ex.fulfill).cancel()
            wait(for: [ex], timeout: 1)
        }

        helper(error: Error.dummy)
        helper(error: Error.cancelled)
    }

    func test__full_recover__fulfilled_path() {
        let ex = expectation(description: "")
        Promise.value(1).cancellize().recover { _ -> CancellablePromise<Int> in
            XCTFail()
            return Promise.value(2).cancellize()
        }.done { _ in
            XCTFail()
        }.catch(policy: .allErrors) { error in
            error.isCancelled ? ex.fulfill() : XCTFail()
        }.cancel()
        wait(for: [ex], timeout: 1)
    }

    func test__conditional_recover() {
        func helper(policy: CatchPolicy, error: Swift.Error, line: UInt = #line) {
            let ex = expectation(description: "\(policy) \(error) \(line)")
            var x = 0
            CancellablePromise<Int>(error: error).recover(policy: policy) { (err: Swift.Error) throws -> CancellablePromise<Int> in
                guard x < 1 else {
                    throw err
                }
                x += 1
                return Promise.value(x).cancellize()
            }.done { _ in
                ex.fulfill()
            }.catch(policy: .allErrors) { error in
                if policy == .allErrorsExceptCancellation {
                    error.isCancelled ? ex.fulfill() : XCTFail()
                } else {
                    XCTFail()
                }
            }.cancel()
            wait(for: [ex], timeout: 1)
        }

        for error in [Error.dummy as Swift.Error, Error.cancelled] {
            helper(policy: .allErrors, error: error)
        }
        helper(policy: .allErrorsExceptCancellation, error: Error.dummy)
    }

    func test__conditional_recover__no_recover() {

        func helper(policy: CatchPolicy, error: Error, line: UInt = #line) {
            let ex = expectation(description: "\(policy) \(error) \(line)")
            CancellablePromise<Int>(error: error).recover(policy: policy) { err -> CancellablePromise<Int> in
                throw err
            }.catch(policy: .allErrors) {
                if !(($0 as? PMKError)?.isCancelled ?? false) {
                    XCTAssertEqual(error, $0 as? Error)
                }
                ex.fulfill()
            }.cancel()
            wait(for: [ex], timeout: 1)
        }

        for error in [Error.dummy, Error.cancelled] {
            helper(policy: .allErrors, error: error)
        }
        helper(policy: .allErrorsExceptCancellation, error: Error.dummy)
    }

    func test__conditional_recover__ignores_cancellation_but_fed_cancellation() {
        let ex = expectation(description: "")
        CancellablePromise<Int>(error: Error.cancelled).recover(policy: .allErrorsExceptCancellation) { _ -> CancellablePromise<Int> in
            XCTFail()
            return Promise.value(1).cancellize()
        }.catch(policy: .allErrors) {
            XCTAssertEqual(Error.cancelled, $0 as? Error)
            ex.fulfill()
        }.cancel()
        wait(for: [ex], timeout: 1)
    }

    func test__conditional_recover__fulfilled_path() {
        let ex = expectation(description: "")
        Promise.value(1).cancellize().recover { err -> CancellablePromise<Int> in
            XCTFail()
            throw err
        }.done {
            XCTFail()
            XCTAssertEqual($0, 1)
        }.catch(policy: .allErrors) { error in
            error.isCancelled ? ex.fulfill() : XCTFail()
        }.cancel()
        wait(for: [ex], timeout: 1)
    }

    func test__cancellable_conditional_recover__fulfilled_path() {
        let ex = expectation(description: "")
        Promise.value(1).cancellize().recover { err -> Promise<Int> in
            XCTFail()
            throw err
        }.done {
            XCTFail()
            XCTAssertEqual($0, 1)
        }.catch(policy: .allErrors) { error in
            error.isCancelled ? ex.fulfill() : XCTFail()
        }.cancel()
        wait(for: [ex], timeout: 1)
    }

    func testEnsureThen_Error() {
        let ex = expectation(description: "")

        let p = Promise.value(1).cancellize().done {
            XCTAssertEqual($0, 1)
            throw Error.dummy
        }.ensureThen {
            return after(seconds: 0.01).cancellize()
        }.catch(policy: .allErrors) {
            XCTAssert(($0 as? PMKError)?.isCancelled ?? false)
        }.finally {
            ex.fulfill()
        }
        p.cancel()

        wait(for: [ex], timeout: 1)
    }

    func testEnsureThen_Value() {
        let ex = expectation(description: "")

        Promise.value(1).cancellize().ensureThen {
            after(seconds: 0.01).cancellize()
        }.done { _ in
            XCTFail()
        }.catch(policy: .allErrors) {
            if !$0.isCancelled {
                XCTFail()
            }
        }.finally {
            ex.fulfill()
        }.cancel()

        wait(for: [ex], timeout: 1)
    }
    
    func testEnsureThen_Value_NotCancelled() {
        let ex = expectation(description: "")

        Promise.value(1).cancellize().ensureThen {
            after(seconds: 0.01).cancellize()
        }.done {
            XCTAssertEqual($0, 1)
        }.catch(policy: .allErrors) { _ in
            XCTFail()
        }.finally {
            ex.fulfill()
        }

        wait(for: [ex], timeout: 1)
    }
    
    func testCancellableFinalizerHelpers() {
        let ex = expectation(description: "")

        let f = Promise.value(1).cancellize().done { _ in
            XCTFail()
        }.catch(policy: .allErrors) {
            $0.isCancelled ? ex.fulfill() : XCTFail()
        }
        f.cancel()

        XCTAssertEqual(f.isCancelled, true)
        XCTAssertEqual(f.cancelAttempted, true)
        XCTAssert(f.cancelledError?.isCancelled ?? false)

        wait(for: [ex], timeout: 1)
    }

    func testCancellableRecoverFromError() {
        let ex = expectation(description: "")

        let p = Promise(error: PMKError.emptySequence).cancellize().recover(policy: .allErrors) { _ in
            Promise.value(1)
        }.done {
            XCTAssertEqual($0, 1)
            ex.fulfill()
        }
        let f = p.catch(policy: .allErrors) { _ in
            XCTFail()
        }
        
        XCTAssertEqual(f.isCancelled, false)
        XCTAssertEqual(f.cancelAttempted, false)
        XCTAssert(f.cancelledError == nil)
        XCTAssert(p.cancelledError == nil)
        
        wait(for: [ex], timeout: 1)

        XCTAssertEqual(p.isPending, false)
        XCTAssertEqual(p.isResolved, true)
        XCTAssertEqual(p.isFulfilled, true)        
    }
}

private enum Error: CancellableError {
    case dummy
    case cancelled

    var isCancelled: Bool {
        return self == Error.cancelled
    }
}
