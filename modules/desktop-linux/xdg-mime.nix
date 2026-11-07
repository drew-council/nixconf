# set default applications
{
  flake.modules.homeManager.desktop-linux =
    { lib, ... }:
    {
      xdg.configFile."mimeapps.list".force = lib.mkForce true;
      xdg.mimeApps = {
        enable = true;
        defaultApplications =
          let
            browser = "zen-beta.desktop";
            fileManager = "org.kde.dolphin.desktop";
            editor = "dev.zed.Zed.desktop";
            imageViewer = "feh.desktop";
            videoPlayer = "mpv.desktop";
          in
          {
            "text/html" = browser;
            "x-scheme-handler/http" = browser;
            "x-scheme-handler/https" = browser;
            "x-scheme-handler/about" = browser;
            "x-scheme-handler/unknown" = browser;
            "inode/directory" = fileManager;
            "text/plain" = editor;
            "application/pdf" = "org.kde.okular.desktop";
            "image/jpeg" = imageViewer;
            "image/png" = imageViewer;
            "image/gif" = imageViewer;
            "image/bmp" = imageViewer;
            "image/tiff" = imageViewer;
            "image/x-bmp" = imageViewer;
            "image/x-pcx" = imageViewer;
            "image/x-tga" = imageViewer;
            "image/x-portable-pixmap" = imageViewer;
            "image/x-portable-bitmap" = imageViewer;
            "image/x-targa" = imageViewer;
            "image/x-portable-greymap" = imageViewer;
            "application/pcx" = imageViewer;
            "image/svg+xml" = imageViewer;
            "video/mp4" = videoPlayer;
            "video/mpeg" = videoPlayer;
            "video/webm" = videoPlayer;
            "video/x-matroska" = videoPlayer;
            "video/x-msvideo" = videoPlayer;
            "video/x-flv" = videoPlayer;
            "video/3gpp" = videoPlayer;
            "video/3gpp2" = videoPlayer;
            "video/quicktime" = videoPlayer;
            "video/x-wmv" = videoPlayer;
            "video/x-crf" = videoPlayer;
            "video/x-ogg" = videoPlayer;
            "video/ogg" = videoPlayer;
            "video/x-theora" = videoPlayer;
            "video/x-dirac" = videoPlayer;
            "video/mp2t" = videoPlayer;
          };
      };
    };
}
