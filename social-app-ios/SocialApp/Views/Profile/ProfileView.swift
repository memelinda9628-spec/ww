import SwiftUI

struct ProfileView: View {
    @State private var vm = ProfileViewModel()

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    VStack(spacing: 12) {
                        AvatarView(url: vm.profile?.avatarUrl, name: vm.profile?.displayName ?? "", size: 72)
                        Text(vm.profile?.displayName ?? "用户")
                            .font(.title2.weight(.semibold))
                        if let bio = vm.profile?.bio, !bio.isEmpty {
                            Text(bio).font(.subheadline).foregroundColor(.secondary)
                        }
                        if let location = vm.profile?.location, !location.isEmpty {
                            Label(location, systemImage: "location.fill")
                                .font(.caption).foregroundColor(.secondary)
                        }
                        HStack(spacing: 40) {
                            NavigationLink {
                                FollowingListView(userIds: vm.followingList)
                            } label: {
                                VStack {
                                    Text("\(vm.followingCount)").font(.headline)
                                    Text("关注").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                MyMomentsView(moments: vm.myMoments)
                            } label: {
                                VStack {
                                    Text("\(vm.profile?.momentsCount ?? 0)").font(.headline)
                                    Text("动态").font(.caption).foregroundColor(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }

                // Quick actions
                Section {
                    NavigationLink {
                        MyMomentsView(moments: vm.myMoments)
                    } label: {
                        Label("我的动态", systemImage: "rectangle.grid.1x2")
                    }
                    NavigationLink {
                        FollowingListView(userIds: vm.followingList)
                    } label: {
                        Label("关注列表", systemImage: "person.2")
                    }
                    Button {
                        vm.showEditProfile = true
                    } label: {
                        Label("编辑资料", systemImage: "pencil")
                    }
                }
            }
            .navigationTitle("我的")
            .sheet(isPresented: $vm.showEditProfile) {
                EditProfileSheet(
                    bio: vm.profile?.bio ?? "",
                    location: vm.profile?.location ?? ""
                ) { bio, location in
                    await vm.updateBio(bio)
                    await vm.updateLocation(location)
                }
            }
        }
        .task { await vm.fetchProfile() }
    }
}