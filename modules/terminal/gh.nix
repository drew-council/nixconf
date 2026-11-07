{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    {
      programs.gh = {
        enable = true;
        extensions = with pkgs; [
          gh-s
          gh-i
          gh-f
          gh-markdown-preview
          gh-stack
        ];
        settings = {
          git_protocol = "ssh";
          aliases = {
            cs = "copilot suggest";
            ce = "copilot explain";
          };
        };
      };

      programs.gh-dash = {
        enable = true;
        settings = {
          pager.diff = "delta";
          prSections =
            let
              needReview = "is:open draft:false review:required";
            in
            [
              {
                title = "need my approval";
                filters = needReview + " -review:approved-by:@me -author:@me";
              }
              {
                title = "mine";
                filters = "is:open author:@me";
                layout.author.hidden = true;
              }
              {
                title = "review requested";
                filters = "is:open review-requested:@me";
              }
              {
                title = "all ready";
                filters = "is:open draft:false";
              }
              {
                title = "all";
                filters = "is:open";
              }
              {
                title = "need review";
                filters = needReview;
              }
            ];
        };
      };
    };
}
