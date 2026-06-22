//
//  LibraryExpanderWebView.swift
//  AtmosAMPlayer
//
//  Created by Peter Luedtke on 2026-06-22.
//


//
//  LibraryExpanderWebView.swift
//  macOS Music Player
//
//  Created for Xcode Native Compile on 2026-06-22.
//  SPDX-License-Identifier: Apache-2.0
//

import SwiftUI
import WebKit

struct LibraryExpanderWebView: View {
    @State private var isLoading = true
    @State private var webView = WKWebView()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header bar for control feedback
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "plus.app.fill")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                    Text("Expand Music Library (am-dl)")
                        .font(.system(size: 13, weight: .bold))
                }
                
                Spacer()
                
                // Navigation controls
                HStack(spacing: 12) {
                    Button(action: { webView.goBack() }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .disabled(!webView.canGoBack)
                    
                    Button(action: { webView.goForward() }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .disabled(!webView.canGoForward)
                    
                    Button(action: { webView.reload() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.plain)
                }
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.04))
            
            Divider()
                
            // The WebKit frame
            WKWebViewRepresentable(webView: webView, isLoading: $isLoading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct WKWebViewRepresentable: NSViewRepresentable {
    let webView: WKWebView
    @Binding var isLoading: Bool
    
    func makeNSView(context: Context) -> WKWebView {
        webView.navigationDelegate = context.coordinator
        
        let url = URL(string: "https://am-dl.pages.dev/")!
        let request = URLRequest(url: url)
        webView.load(request)
        
        // Transparent style support
        webView.setValue(false, forKey: "drawsBackground")
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WKWebViewRepresentable
        
        init(_ parent: WKWebViewRepresentable) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            parent.isLoading = true
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.isLoading = false
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            parent.isLoading = false
        }
    }
}
