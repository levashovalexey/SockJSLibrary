//
//  SockJSService.swift
//  SockJS
//
//  Created by Alexey Levashov on 8/20/20.
//  Copyright © 2020 Alexey Levashov. All rights reserved.
//

import SwiftyJSON
import Foundation

struct StompCommands {
    // Basic Commands
    static let commandConnect = "CONNECT"
    static let commandSend = "SEND"
    static let commandSubscribe = "SUBSCRIBE"
    static let commandUnsubscribe = "UNSUBSCRIBE"
    static let commandBegin = "BEGIN"
    static let commandCommit = "COMMIT"
    static let commandAbort = "ABORT"
    static let commandAck = "ACK"
    static let commandDisconnect = "DISCONNECT"
    static let commandPing = "\n"

    static let controlChar = String(format: "%C", arguments: [0x00])

    // Ack Mode
    static let ackClientIndividual = "client-individual"
    static let ackClient = "client"
    static let ackAuto = "auto"
    // Header Commands
    static let commandHeaderReceipt = "receipt"
    static let commandHeaderDestination = "destination"
    static let commandHeaderDestinationId = "id"
    static let commandHeaderContentLength = "content-length"
    static let commandHeaderContentType = "content-type"
    static let commandHeaderAck = "ack"
    static let commandHeaderTransaction = "transaction"
    static let commandHeaderMessageId = "id"
    static let commandHeaderSubscription = "subscription"
    static let commandHeaderDisconnected = "disconnected"
    static let commandHeaderHeartBeat = "heart-beat"
    static let commandHeaderAcceptVersion = "accept-version"
    // Header Response Keys
    static let responseHeaderSession = "session"
    static let responseHeaderReceiptId = "receipt-id"
    static let responseHeaderErrorMessage = "message"
    // Frame Response Keys
    static let responseFrameConnected = "CONNECTED"
    static let responseFrameMessage = "MESSAGE"
    static let responseFrameReceipt = "RECEIPT"
    static let responseFrameError = "ERROR"
}


public class SockJSService: NSObject, SockJSServiceProtocol {

    // MARK: - Private Variables

    private var _url: String

    private var socket: WebSocketService?
    private var sessionId: String?

    private var connectionHeaders: [String: String]?
    private var requestCookies: [HTTPCookie]?

    private var urlRequest: URLRequest?

    // MARK: - Public Variables

    public var connection: Bool = false

    weak var delegate: SockJSServiceDelegate?

    // MARK: - Init

    private init(url: String) {
        _url = url
    }

    // MARK: - Public

    func sendJSONForDict(dict: AnyObject, toDestination destination: String) {
        do {
            let theJSONData = try JSONSerialization.data(withJSONObject: dict, options: JSONSerialization.WritingOptions())
            let theJSONText = String(data: theJSONData, encoding: String.Encoding.utf8)
            let header = [StompCommands.commandHeaderContentType:"application/json;charset=UTF-8"]
            sendMessage(message: theJSONText!, toDestination: destination, withHeaders: header, withReceipt: nil)
        } catch {
            print("error serializing JSON: \(error)")
        }
    }

    func openSocketWithURLRequest(request: URLRequest, delegate: SockJSServiceDelegate, connectionHeaders: [String: String]? = nil, requestCookies: [HTTPCookie]? = nil) {
        self.connectionHeaders = connectionHeaders
        self.delegate = delegate
        self.urlRequest = request
        // Opening the socket
        openSocket()
        self.connection = true
    }

    func sendMessage(message: String, toDestination destination: String, withHeaders headers: [String : String]?, withReceipt receipt: String?) {
        var headersToSend = [String: String]()
        if let headers = headers {
            headersToSend = headers
        }

        // Setting up the receipt.
        if let receipt = receipt {
            headersToSend[StompCommands.commandHeaderReceipt] = receipt
        }

        headersToSend[StompCommands.commandHeaderDestination] = destination

        // Setting up the content length.
        let contentLength = message.utf8.count
        headersToSend[StompCommands.commandHeaderContentLength] = "\(contentLength)"

        // Setting up content type as plain text.
        if headersToSend[StompCommands.commandHeaderContentType] == nil {
            headersToSend[StompCommands.commandHeaderContentType] = "text/plain"
        }
        sendFrame(command: StompCommands.commandSend, header: headersToSend, body: message as AnyObject)
    }

    func isConnected() -> Bool {
        return connection
    }

    func subscribe(destination: String) {
        connection = true
        subscribeToDestination(destination: destination, ackMode: .AutoMode)
    }

    func subscribeToDestination(destination: String, ackMode: StompAckMode) {
        var ack = ""
        switch ackMode {
        case StompAckMode.ClientMode:
            ack = StompCommands.ackClient
            break
        case StompAckMode.ClientIndividualMode:
            ack = StompCommands.ackClientIndividual
            break
        default:
            ack = StompCommands.ackAuto
            break
        }
        var headers = [String:String]()
            
        headers[StompCommands.commandHeaderDestinationId] = destination != "" ? destination : ""
        headers[StompCommands.commandHeaderDestination] = destination
        headers[StompCommands.commandHeaderAck] = ack
        
        self.sendFrame(command: StompCommands.commandSubscribe, header: headers, body: nil)
    }

    func subscribeWithHeader(destination: String, withHeader header: [String: String]) {
        var headerToSend = header
        headerToSend[StompCommands.commandHeaderDestination] = destination
        sendFrame(command: StompCommands.commandSubscribe, header: headerToSend, body: nil)
    }

    func disconnect() {
        connection = false
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandDisconnect] = String(Int(NSDate().timeIntervalSince1970))
        sendFrame(command: StompCommands.commandDisconnect, header: headerToSend, body: nil)
        // Close the socket to allow recreation
        self.closeSocket()
    }

    func reconnect(request: URLRequest, delegate: SockJSServiceDelegate, connectionHeaders: [String : String], time: Double) {
        Timer.scheduledTimer(withTimeInterval: time, repeats: true, block: { _ in
            self.reconnectLogic(request: request, delegate: delegate
                , connectionHeaders: connectionHeaders)
        })
    }

    func autoDisconnect(time: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + time) {
            // Disconnect the socket
            self.disconnect()
        }
    }

    func unsubscribe(destination: String) {
        connection = false
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderDestinationId] = destination
        sendFrame(command: StompCommands.commandUnsubscribe, header: headerToSend, body: nil)
    }

    func begin(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandBegin, header: headerToSend, body: nil)
    }

    func commit(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandCommit, header: headerToSend, body: nil)
    }

    func abort(transactionId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderTransaction] = transactionId
        sendFrame(command: StompCommands.commandAbort, header: headerToSend, body: nil)
    }

    func ack(messageId: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }

    func ack(messageId: String, withSubscription subscription: String) {
        var headerToSend = [String: String]()
        headerToSend[StompCommands.commandHeaderMessageId] = messageId
        headerToSend[StompCommands.commandHeaderSubscription] = subscription
        sendFrame(command: StompCommands.commandAck, header: headerToSend, body: nil)
    }

    // MARK: - Private

    private func openSocket() {
        guard let request = urlRequest else {
            return
        }
        self.socket = WebSocketService()
        socket?.delegate = self
        socket?.connect(urlRequest: request)
    }

    private func closeSocket(){
        DispatchQueue.main.async {
            self.delegate?.sockjsClientDidDisconnect(client: self)
            if self.socket != nil {
                // Close the socket
                self.socket?.disconnect()
                self.socket?.delegate = nil
                self.socket = nil
            }
        }
    }

    private func connect() {
        // Support for Spring Boot 2.1.x
        if connectionHeaders == nil {
            connectionHeaders = [StompCommands.commandHeaderAcceptVersion:"1.1,1.2"]
        } else {
            connectionHeaders?[StompCommands.commandHeaderAcceptVersion] = "1.1,1.2"
        }
        // at the moment only anonymous logins
        self.sendFrame(command: StompCommands.commandConnect, header: connectionHeaders, body: nil)
    }

    private func reconnectLogic(request: URLRequest, delegate: SockJSServiceDelegate, connectionHeaders: [String: String] = [String: String]()){
        // Check if connection is alive or dead
        if (!self.isConnected()){
            self.checkConnectionHeader(connectionHeaders: connectionHeaders) ? self.openSocketWithURLRequest(request: request, delegate: delegate, connectionHeaders: connectionHeaders) : self.openSocketWithURLRequest(request: request, delegate: delegate)
        }
    }

    private func checkConnectionHeader(connectionHeaders: [String: String] = [String: String]()) -> Bool{
        if (connectionHeaders.isEmpty){
            // No connection header
            return false
        } else {
            // There is a connection header
            return true
        }
    }

    // MARK: - Receiving

    private func destinationFromHeader(header: [String: String]) -> String {
        for (key, _) in header {
            if key == "destination" {
                let destination = header[key]!
                return destination
            }
        }
        return ""
    }

    private func dictForJSONString(jsonStr: String?) ->  [String: Any]? {
        if let jsonStr = jsonStr {
            do {
                if let data = jsonStr.data(using: String.Encoding.utf8) {
                    let json = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any]
                    return json
                }
            } catch {
                print("error serializing JSON: \(error)")
            }
        }
        return nil
    }

    private func receiveFrame(command: String, headers: [String: String], body: String?) {
        if command == StompCommands.responseFrameConnected {
            // Connected
            if let sessId = headers[StompCommands.responseHeaderSession] {
                sessionId = sessId
            }

            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.sockjsClientDidConnect(client: self)
                })
            }
        } else if command == StompCommands.responseFrameMessage {   // Message comes to this part
            // Response
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.sockjsClient(client: self, didReceiveMessageWithJSONBody: JSON(parseJSON: body ?? ""), akaStringBody: body, withHeader: headers, withDestination: self.destinationFromHeader(header: headers))
                })
            }
        } else if command == StompCommands.responseFrameReceipt {   //
            // Receipt
            if let delegate = delegate {
                if let receiptId = headers[StompCommands.responseHeaderReceiptId] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendReceipt(client: self, withReceiptId: receiptId)
                    })
                }
            }
        } else if command.count == 0 {
            // Pong from the server
            socket?.sendMessage(message: StompCommands.commandPing)
            //socket?.send(StompCommands.commandPing)
            if let delegate = delegate {
                DispatchQueue.main.async(execute: {
                    delegate.serverDidSendPing()
                })
            }
        } else if command == StompCommands.responseFrameError {
            // Error
            if let delegate = delegate {
                if let msg = headers[StompCommands.responseHeaderErrorMessage] {
                    DispatchQueue.main.async(execute: {
                        delegate.serverDidSendError(client: self, withErrorMessage: msg, detailedErrorMessage: body)
                    })
                }
            }
        }
    }

    private func processString(string: String) {
        var contents = string.components(separatedBy: "\n")
        if contents.first == "" {
            contents.removeFirst()
        }

        if let command = contents.first {
            var headers = [String: String]()
            var body = ""
            var hasHeaders  = false

            contents.removeFirst()
            for line in contents {
                if hasHeaders == true {
                    body += line
                } else {
                    if line == "" {
                        hasHeaders = true
                    } else {
                        let parts = line.components(separatedBy: ":")
                        if let key = parts.first {
                            headers[key] = parts.dropFirst().joined(separator: ":")
                        }
                    }
                }
            }

            // Remove the garbage from body
            if body.hasSuffix("\0") {
                body = body.replacingOccurrences(of: "\0", with: "")
            }

            receiveFrame(command: command, headers: headers, body: body)
        }
    }

    // MARK: - Sending

    private func sendFrame(command: String?, header: [String: String]?, body: AnyObject?) {
        var frameString = ""
        if command != nil {
            frameString = command! + "\n"
        }

        if let header = header {
            for (key, value) in header {
                frameString += key
                frameString += ":"
                frameString += value
                frameString += "\n"
            }
        }

        if let body = body as? String {
            frameString += "\n"
            frameString += body
        } else if let _ = body as? NSData {

        }

        if body == nil {
            frameString += "\n"
        }

        frameString += StompCommands.controlChar

        socket?.sendMessage(message: frameString)
    }
}

extension SockJSService: WebSocketDelegate {

    func didOpen(socket: WebSocketServiceProtocol) {
        connect()
    }

    func didClose(socket: WebSocketServiceProtocol, code: Int, reason: String?) {
        DispatchQueue.main.async {
            self.delegate?.sockjsClientDidDisconnect(client: self)
        }
    }

    func didReceiveMessage(socket: WebSocketServiceProtocol, message: String) {
        processString(string: message)
    }

    func didReceiveData(socket: WebSocketServiceProtocol, data: Data) {
        if let msg = String(data: data, encoding: String.Encoding.utf8) {
            processString(string: msg)
        }
    }
    func didErrorOccured(socket: WebSocketServiceProtocol, error: Error) {
        DispatchQueue.main.async {
            self.delegate?.serverDidSendError(client: self, withErrorMessage: "", detailedErrorMessage: "")
        }
    }
}
