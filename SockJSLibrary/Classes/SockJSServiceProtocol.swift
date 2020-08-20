//
//  SockJSServiceProtocol.swift
//  SockJS
//
//  Created by Alexey Levashov on 8/20/20.
//  Copyright © 2020 Alexey Levashov. All rights reserved.
//

import SwiftyJSON
import Foundation

public enum StompAckMode {
    case AutoMode
    case ClientMode
    case ClientIndividualMode
}

protocol SockJSServiceProtocol {
    func sendJSONForDict(dict: AnyObject, toDestination destination: String)
    func openSocketWithURLRequest(request: URLRequest, delegate: SockJSServiceDelegate, connectionHeaders: [String: String]?, requestCookies: [HTTPCookie]?)
    func sendMessage(message: String, toDestination destination: String, withHeaders headers: [String: String]?, withReceipt receipt: String?)

    func disconnect()
    func reconnect(request: URLRequest, delegate: SockJSServiceDelegate, connectionHeaders: [String: String], time: Double)
    func autoDisconnect(time: Double)

    func isConnected() -> Bool
    func subscribe(destination: String)
    func subscribeToDestination(destination: String, ackMode: StompAckMode)
    func subscribeWithHeader(destination: String, withHeader header: [String: String])
    func unsubscribe(destination: String)

    func begin(transactionId: String)
    func commit(transactionId: String)
    func abort(transactionId: String)
    func ack(messageId: String)
    func ack(messageId: String, withSubscription subscription: String)
}

protocol SockJSServiceDelegate: class {
    func sockjsClient(client: SockJSServiceProtocol!, didReceiveMessageWithJSONBody jsonBody: JSON, akaStringBody stringBody: String?, withHeader header:[String: String]?, withDestination destination: String)

    func sockjsClientDidDisconnect(client: SockJSServiceProtocol!)
    func sockjsClientDidConnect(client: SockJSServiceProtocol!)
    func serverDidSendReceipt(client: SockJSServiceProtocol!, withReceiptId receiptId: String)
    func serverDidSendError(client: SockJSServiceProtocol!, withErrorMessage description: String, detailedErrorMessage message: String?)
    func serverDidSendPing()
}
