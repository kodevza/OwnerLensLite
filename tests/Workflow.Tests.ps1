Describe "OwnerLensLite CI workflow" {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
  }

  It "installs the rich console dependency before running tests" {
    $workflow = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot ".github/workflows/publish.yml")

    $workflow | Should -Match "Install-Module PwshRichLite"
  }

  It "imports the installed rich console dependency when no local checkout is available" {
    $testImporter = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot "tests/Support/Import-OwnerLensLiteTestFunctions.ps1")

    $testImporter | Should -Match "Import-Module PwshRichLite"
  }

  It "uses the Lite project name throughout test sources" {
    $legacyName = "OwnerLens" + "Light"
    $testSources = Get-ChildItem -Path $PSScriptRoot -Filter "*.ps1" -File -Recurse

    $legacyReferences = @(
      $testSources | Where-Object { (Get-Content -Raw -LiteralPath $_.FullName).Contains($legacyName) }
    )

    $legacyReferences | Should -BeNullOrEmpty
  }
}
