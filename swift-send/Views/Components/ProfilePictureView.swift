//
//  ProfilePictureView.swift
//  swift-send
//
//  Extracted from ChatDetailView.swift on 10/23/25.
//  Reusable profile picture component.
//

import SwiftUI

/// Reusable profile picture view
/// Displays user's profile picture or a default placeholder
struct ProfilePictureView: View {
    let photoURL: String?
    let size: CGFloat
    
    init(photoURL: String? = nil, size: CGFloat = 40) {
        self.photoURL = photoURL
        self.size = size
    }
    
    var body: some View {
        Group {
            if let urlString = photoURL, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        defaultProfileImage
                    @unknown default:
                        defaultProfileImage
                    }
                }
            } else {
                defaultProfileImage
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 1))
    }
    
    private var defaultProfileImage: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundColor(.gray)
    }
}

