//
//  ContentView.swift
//  GithubDahboard
//
//  Created by toddoon on 14/08/2026.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct ContentView: View {
    @State private var viewModel = GitHubViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if viewModel.user == nil {
                    authSection
                    Divider()
                }
                contentSection
            }
            .padding()
            .navigationTitle("GitHub Dashboard")
            .task { await viewModel.start() }
            .toolbar {
                if viewModel.user != nil {
                    ToolbarItem(placement: .automatic) {
                        Button {
                            Task { await viewModel.loadAuthenticatedUser() }
                        } label: {
                            Label("Rafraîchir", systemImage: "arrow.clockwise")
                        }
                        .disabled(viewModel.isLoading)
                    }
                    #if os(macOS)
                    ToolbarItem(placement: .automatic) {
                        Button(role: .destructive) {
                            viewModel.logout()
                        } label: {
                            Label("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    #else
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            viewModel.logout()
                        } label: {
                            Label("Déconnexion", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    }
                    #endif
                }
            }
        }
    }

    private var authSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let code = viewModel.deviceCode, let uri = viewModel.verificationURI {
                Text(code)
                    .font(.title)
                    .monospaced()
                    .textSelection(.enabled)
                Button("Copier le code") { copy(code) }
                Link("Ouvrir github.com/login/device", destination: uri)
                HStack {
                    ProgressView()
                    Text("En attente de validation…")
                    Button("Annuler") { viewModel.cancelSignIn() }
                }
            } else {
                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    Label("Se connecter avec GitHub", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderedProminent)
            }
            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    @ViewBuilder
    private var contentSection: some View {
        if let user = viewModel.user {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .center, spacing: 12) {
                        AsyncImage(url: user.avatar_url) { phase in
                            switch phase {
                            case .empty: ProgressView()
                            case .success(let image): image.resizable().scaledToFill()
                            case .failure: Image(systemName: "person.crop.circle.fill")
                                    .resizable().scaledToFit()
                            @unknown default: EmptyView()
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())

                        VStack(alignment: .leading) {
                            Text(user.name ?? user.login)
                                .font(.title2).bold()
                            Text("@\(user.login)")
                                .foregroundStyle(.secondary)
                            if let bio = user.bio, !bio.isEmpty {
                                Text(bio)
                                    .font(.callout)
                            }
                            HStack(spacing: 12) {
                                Label("\(user.followers ?? 0) followers", systemImage: "person.2")
                                Label("\(user.public_repos ?? 0) repos", systemImage: "folder")
                            }
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    if let error = viewModel.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                    ATraiterView(data: viewModel.aTraiter, warning: viewModel.aTraiterWarning)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .refreshable {
                await viewModel.loadAuthenticatedUser()
            }
        } else {
            ContentUnavailableView("Non connecté", systemImage: "person.crop.circle.badge.questionmark", description: Text("Connectez-vous avec GitHub pour voir vos PR et vos tâches."))
        }
    }

    private func copy(_ code: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        #else
        UIPasteboard.general.string = code
        #endif
    }
}

#Preview {
    ContentView()
}
