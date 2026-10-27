import SwiftUI

extension EnvironmentValues {
    /// Where the pictures captured with posts are read from.
    @Entry var sourcePictures = SourcePictures(directory: nil)
}
