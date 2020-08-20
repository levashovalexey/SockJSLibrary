//
//  WebSocketService.swift
//  SockJS
//
//  Created by Alexey Levashov on 8/20/20.
//  Copyright © 2020 Alexey Levashov. All rights reserved.
//

import Foundation
import Network

class WebSocketService: NSObject, WebSocketServiceProtocol {

    // MARK: - Private Variables

    private var webSocketTask: URLSessionWebSocketTask?

    // MARK: - Public methods

    public func connect(urlRequest: URLRequest) {
        let urlSession = URLSession(configuration: .default, delegate: self, delegateQueue: OperationQueue())
        webSocketTask = urlSession.webSocketTask(with: urlRequest)
        webSocketTask?.resume()
        receiveMessage()
    }

    public func connect(url: URL) {
        connect(urlRequest: URLRequest(url: url))
    }

    public func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
    }

    public func sendMessage(message: String) {
        webSocketTask?.send(.string(message), completionHandler: { (error) in
            if let error = error {
                self.delegate?.didErrorOccured(socket: self, error: error)
            }
        })
    }

    var delegate: WebSocketDelegate?

    // MARK: Private methods

    private func receiveMessage() {
        webSocketTask?.receive { result in
          switch result {
            case .failure(let error):
                self.delegate?.didErrorOccured(socket: self, error: error)
            case .success(let message):
            switch message {
                case .string(let text):
                    self.delegate?.didReceiveMessage(socket: self, message: text)
                case .data(let data):
                    self.delegate?.didReceiveData(socket: self, data: data)
                @unknown default:
                    fatalError("Unexpected message")
                }
            }
            self.receiveMessage()
        }
    }
}

extension WebSocketService: URLSessionWebSocketDelegate {

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        delegate?.didOpen(socket: self)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        var reasonString: String?
        if let data: Data = reason {
            reasonString = String(decoding: data, as: UTF8.self)
        }
        delegate?.didClose(socket: self, code: closeCode.rawValue, reason: reasonString)
    }
}
