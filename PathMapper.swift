//
//  PathMapper.swift
//  PlexDAPCompanion
//
//  Created by Sebastian Lidbetter on 2026-01-28.
//

import Foundation

struct PathMapper {

    let plexPrefix: String
    let dapPrefix: String

    func map(_ plexPath: String) -> String? {
        guard plexPath.hasPrefix(plexPrefix) else {
            return nil
        }

        let relativePath = plexPath
            .replacingOccurrences(of: plexPrefix, with: "")

        return dapPrefix + relativePath
    }
}
