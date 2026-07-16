# Cask do Maestro para o tap do Homebrew (vai em Casks/maestro.rb no repo do tap).
# Atualizar a cada release: version, sha256 (saída do scripts/release.sh) e URL se mudar.
cask "maestro" do
  version "0.1.0"
  sha256 "PREENCHER_COM_O_SHA256_DA_RELEASE"

  url "https://github.com/kelvynkrug/maestro/releases/download/v#{version}/Maestro-#{version}.zip"
  name "Maestro"
  desc "Controle de volume e saída de áudio por aplicativo"
  homepage "https://github.com/kelvynkrug/maestro"

  depends_on macos: ">= :sequoia"

  app "Maestro.app"

  zap trash: [
    "~/Library/Preferences/com.kelvynkrug.maestro.plist",
  ]
end
