import Nuke

extension ImageRequest.UserInfoKey {
    static let isMangaCover: Self = "aidoku/isMangaCover"
}

enum CoverDataCache {
    static let cache: DataCache? = {
        let cache = try? DataCache(name: "org.ry-st.Aidoku.covercache")
        cache?.sizeLimit = 500 * 1024 * 1024
        return cache
    }()
}
