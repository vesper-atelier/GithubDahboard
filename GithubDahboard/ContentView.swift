//
//  ContentView.swift
//  GithubDahboard
//
//  Created by toddoon on 14/08/2026.
//

import SwiftUI

struct ContentView: View {
    @State private var viewModel = GitHubViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                tokenSection
                Divider()
                contentSection
            }
            .padding()
            .navigationTitle("GitHub Dashboard")
            .toolbar {
                if viewModel.user != nil {
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

    private var tokenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Token GitHub (pat_...)")
                .font(.headline)
            HStack {
                SecureField("Collez votre token personnel", text: $viewModel.token)
                Button {
                    viewModel.token = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Effacer le token")
            }
            HStack {
                Button {
                    Task { await viewModel.loadAuthenticatedUser() }
                } label: {
                    Label("Se connecter", systemImage: "bolt.horizontal.circle")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if !viewModel.token.isEmpty, viewModel.user == nil {
                Text("Un token est présent (Keychain).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

                    if !viewModel.repos.isEmpty {
                        Text("Dépôts récents")
                            .font(.headline)
                        ForEach(viewModel.repos) { repo in
                            Link(destination: repo.html_url) {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(repo.name)
                                            .font(.subheadline).bold()
                                        Spacer()
                                        Label("\(repo.stargazers_count)", systemImage: "star")
                                            .labelStyle(.titleAndIcon)
                                            .foregroundStyle(.yellow)
                                    }
                                    if let desc = repo.description, !desc.isEmpty {
                                        Text(desc)
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }
                                    if let lang = repo.language {
                                        Text(lang)
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.thinMaterial, in: Capsule())
                                    }
                                }
                                .padding(.vertical, 8)
                            }
                            Divider()
                        }
                    } else if !viewModel.isLoading {
                        ContentUnavailableView("Aucun dépôt", systemImage: "folder", description: Text("Appuyez sur Se connecter pour charger vos dépôts."))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ContentUnavailableView("Non connecté", systemImage: "person.crop.circle.badge.questionmark", description: Text("Saisissez votre token puis appuyez sur Se connecter."))
        }
    }
}

#Preview {
    ContentView()
}
