//
//  OnboardingView.swift
//  yapLONGER
//
//  Created by Chan Yap Long on 17/11/25.
//
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Onboarding Page Model
struct OnboardingPage: Identifiable {
    let id = UUID()
    let imageName: String
    let title: String
    let description: String
}

// MARK: - Main Onboarding View
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false
    @State private var currentPage = 0
    
    private var safeCurrentPage: Int {
        guard !pages.isEmpty else { return 0 }
        return min(max(currentPage, 0), pages.count - 1)
    }
    
    let pages = [
        OnboardingPage(
            imageName: "light",
            title: "Welcome to Scripties",
            description: "Your personal speech coach. Write, practice, and perfect your presentations with feedback."
        ),
        OnboardingPage(
            imageName: "waveform.circle.fill",
            title: "Practice Your Speech",
            description: "Teleprompter in-app helps you to read naturally, using an autoscroll based on your voice."
        ),
        OnboardingPage(
            imageName: "chart.line.uptrend.xyaxis",
            title: "Get Detailed Feedback",
            description: "Track your words per minute and  speech consistency to improve your delivery."
        ),
        OnboardingPage(
            imageName: "checkmark.seal.fill",
            title: "Ready to Practice!",
            description: "Create, Record, Repeat. Become a confident speaker with Scripties"
        )
    ]
    
    var body: some View {
        ZStack {
            Color.pri.opacity(0.06)
            .ignoresSafeArea()
            
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button("Skip") {
                        completeOnboarding()
                    }
                    .foregroundStyle(Color.pri)
                    .opacity(safeCurrentPage < pages.count - 1 ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: safeCurrentPage)
                    .padding()
                }
                .frame(height: 50)
                
                Spacer()
                
                // TabView for pages (iOS) / custom pager (macOS)
                #if os(macOS)
                ZStack {
                    OnboardingPageView(page: pages[safeCurrentPage])
                        .id(safeCurrentPage)
                        .transition(.opacity)
                }
                .animation(.easeInOut(duration: 0.25), value: safeCurrentPage)
                #else
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        OnboardingPageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .tint(.pri)
                .onChange(of: currentPage) { _, newValue in
                    // Clamp defensively if TabView/animations race
                    let clamped = min(max(newValue, 0), pages.count - 1)
                    if clamped != newValue {
                        currentPage = clamped
                    }
                }
                #endif
                
                Spacer()
                // Navigation buttons
                HStack(spacing: 20) {
                    if safeCurrentPage > 0 {
                        Button(action: {
                            withAnimation(.spring(response: 0.8)) {
                                currentPage = max(0, safeCurrentPage - 1)
                            }
                        }) {
                            HStack {
                                Image(systemName: "chevron.left")
                                    .font(.headline)
                                Text("Back")
                                    .font(.headline)
                            }
                            .foregroundStyle(Color.sec)
                            .frame(width: 100, height: 50)
                            .background(Color.secondary.opacity(0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.sec.opacity(0.25), lineWidth: 1)
                            )
                            .cornerRadius(12)
                            .padding()
                        }
                        .disabled(safeCurrentPage == 0)
                    } else {
                        Spacer()
                            .frame(width: 100)
                    }
                    
                    Spacer()
                    Button(action: {
                        if safeCurrentPage < pages.count - 1 {
                            withAnimation(.spring(response: 0.3)) {
                                currentPage = min(pages.count - 1, safeCurrentPage + 1)
                            }
                        } else {
                            completeOnboarding()
                        }
                    }) {
                        HStack(spacing: 8) {
                            ZStack {
                                Text("Next")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .opacity(safeCurrentPage == pages.count - 1 ? 0 : 1)
                                Text("Get Started")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .opacity(safeCurrentPage == pages.count - 1 ? 1 : 0)
                            }
                            if safeCurrentPage < pages.count - 1 {
                                Image(systemName: "chevron.right")
                                    .font(.headline)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.spring(response: 0.3), value: safeCurrentPage)
                        .foregroundColor(.white)
                        .frame(width: 170, height: 50)
                        .background(
                            Color.pri
                        )
                        .cornerRadius(12)
                        .shadow(color: Color.pri.opacity(0.35), radius: 8, x: 0, y: 4)
                    }
                    .padding()
                }
            }
        }
    }
    
    private func completeOnboarding() {
        withAnimation {
            hasCompletedOnboarding = true
        }
    }
}

// MARK: - Individual Onboarding Page
struct OnboardingPageView: View {
    let page: OnboardingPage
    @State private var isAnimating = false
    @Environment(\.colorScheme) private var colorScheme
    
    private func resolvedImageName(from baseName: String) -> String {
        if baseName == "light" || baseName == "dark" {
            return colorScheme == .dark ? "dark" : "light"
        }
        return baseName
    }
    
    @ViewBuilder
    private func pageImage(named name: String) -> some View {
        let effectiveName = resolvedImageName(from: name)
        #if os(iOS)
        if let uiImage = UIImage(named: effectiveName) {
            // Use asset as-is (no tint)
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
        } else {
            // SF Symbol
            Image(systemName: effectiveName)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(Color.pri)
        }
        #elseif os(macOS)
        if let nsImage = NSImage(named: effectiveName) {
            // Use asset as-is (no tint)
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
        } else {
            // SF Symbol
            Image(systemName: effectiveName)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundStyle(Color.pri)
        }
        #endif
    }
    
    var body: some View {
        VStack(spacing: 30) {
            // Icon with animation
            ZStack {
                Circle()
                    .fill(Color.pri.opacity(0.12))
                    .frame(width: 172, height: 172)
                
                pageImage(named: page.imageName)
                    .padding()
            }
            .padding(.top, 20)
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(.system(size: 28, weight: .bold))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .foregroundStyle(.primary)
                
                Text(page.description)
                    .font(.system(size: 17))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding()
        .onAppear {
            isAnimating = true
        }
    }
}

#Preview("Onboarding") {
    OnboardingView()
}
