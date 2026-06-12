import SwiftUI

struct MyMomentsView: View {
    let moments: [Moment]

    var body: some View {
        List(moments) { moment in
            MomentCard(moment: moment)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .navigationTitle("我的动态")
    }
}