Describe "OwnerLens Light CI workflow" {
  BeforeAll {
    $script:repoRoot = Split-Path -Parent $PSScriptRoot
  }

  It "installs the rich console dependency before running tests" {
    $workflow = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot ".github/workflows/publish.yml")

    $workflow | Should -Match "Install-Module PwshRichLite"
  }

  It "imports the installed rich console dependency when no local checkout is available" {
    $testImporter = Get-Content -Raw -LiteralPath (Join-Path $script:repoRoot "tests/Support/Import-OwnerLensLightTestFunctions.ps1")

    $testImporter | Should -Match "Import-Module PwshRichLite"
  }
}
