<div align="center">

[简体中文](README.md) · [English](README.en.md) · **日本語**

<img src="Assets/AppIcon/AppIcon-1024.png" width="128" alt="Snug アイコン">

# Snug

**Make Your Remote Mac Native on Any Device**

リモート Mac の表示とタッチを強化<br>デバイスごとに専用の画面 · ネイティブなタッチジェスチャー · App ライブラリ

<p>対応リモートアプリ<br><a href="https://uuyc.163.com/"><img src="https://dl.zephyrxiang.com/snug/media/remote-uu.7b92201d.png" width="40" align="absmiddle" alt=""> <b>UU远程</b></a>&emsp;&emsp;<a href="https://github.com/kunkundi/crossdesk"><img src="https://dl.zephyrxiang.com/snug/media/remote-crossdesk.0ffdb226.png" width="40" align="absmiddle" alt=""> <b>CrossDesk</b></a>&emsp;&emsp;<a href="https://github.com/skyvense/snug-sunlogin"><img src="https://dl.zephyrxiang.com/snug/media/remote-sunlogin.2d91a469.png" width="40" align="absmiddle" alt=""> <b>向日葵</b></a><sup>公式対応版</sup></p>

[![Latest release](https://img.shields.io/github/v/release/zephyr4123/snug?label=release&color=blue)](https://github.com/zephyr4123/snug/releases/latest) ![Apple Silicon · Intel](https://img.shields.io/badge/Apple%20Silicon%20%C2%B7%20Intel-Universal-success) ![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue) ![Notarized](https://img.shields.io/badge/Apple-Notarized-black?logo=apple) [![License MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)

[ダウンロード](#-ダウンロード) · [クイックスタート](#-クイックスタート) · [ネイティブな体験](#-すべてのデバイスでネイティブに) · [あらゆるデバイス](#-1-台の-mac-をあらゆるデバイスで) · [App ライブラリ](#-app-ライブラリ) · [スクリーンショット](#-スクリーンショット) · [比較](#-他の方法との比較) · [インストール](#-インストール) · [使い方](#-使い方) · [制限事項](#-既知の制限) · [開発](#-開発)

<br>

<img src="https://dl.zephyrxiang.com/snug/media/hero-architecture.e4ceb0af.png" width="92%" alt="図：Snug はスマートフォン・タブレット・コンピュータそれぞれのために Mac 上に画面を作成し、リモートデスクトップアプリを通じて各デバイスいっぱいに表示します">
<p><sub>▶ <a href="https://dl.zephyrxiang.com/snug/media/phone-demo.a97e46d1.mp4">HD デモ動画を見る</a></sub></p>

</div>

> [!IMPORTANT]
> **向日葵に対応**：向日葵公式による対応版 [Snug for Sunlogin](https://github.com/skyvense/snug-sunlogin) が公開されました。macOS と Windows のホストに対応し、向日葵公式が独立して開発・メンテナンスしています。ダウンロードと問題の報告は同リポジトリへお願いします（[コミュニティ移植版](#-コミュニティ移植版)を参照）。向日葵公式の対応に心より感謝します。
>
> **CrossDesk に対応**：無料・オープンソースのリモートデスクトップアプリ [CrossDesk](https://github.com/kunkundi/crossdesk) に対応しました。画面、ネイティブなジェスチャー、App ライブラリは UU远程 と同じです。初回の設定は[クイックスタート](#-クイックスタート)を参照してください。
>
> **UU远程 の VIP 会員の方へ**：2026 年 12 月 1 日より、UU远程 はマルチディスプレイおよび仮想ディスプレイ機能を VIP に移行します。Snug は仮想ディスプレイ上に構築されています。もし UU远程 の VIP 会員であれば、ぜひお試しください。
>
> **私たちの立場**：Snug は独立したコミュニティプロジェクトであり、UU远程 とは商業的なつながりはありません。購読するかどうかは UU远程 そのものについての判断であり、Snug のためだけに購読する必要はありません。連携部分は差し替え可能なアダプター層に切り出してあるため、他のアプリへの対応を追加する PR やフォークでの独自対応を歓迎します（[開発](#-開発)を参照）。

> [aoyamashou/UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（AoyamaShou 作の UU Remote Companion、MIT ライセンス）を引き継いだもので、元の著作権表示とコミット履歴を完全に保持しています。2.0 でスマートフォン画面を中心に再設計し、2.6 でタブレットとコンピュータに拡張しました。

## 📥 ダウンロード

<img src="Assets/AppIcon/AppIcon-1024.png" width="88" align="left" alt="Snug アイコン">

**Snug for macOS** [![Latest release](https://img.shields.io/github/v/release/zephyr4123/snug?label=release&color=blue)](https://github.com/zephyr4123/snug/releases/latest)<br>Apple シリコンと Intel に対応したユニバーサルパッケージ、macOS 14 以降<br>Apple による署名と公証済み。Applications にドラッグしてインストールします

<br clear="left">

| 入手先 | 備考 | ダウンロード |
| :--- | :--- | :--- |
| **中国ミラー** | Tencent Cloud CDN。中国本土では推奨 | [Snug.dmg](https://dl.zephyrxiang.com/snug/latest/Snug.dmg) |
| **GitHub Releases** | リリースノート、チェックサム、過去のバージョン | [Releases へ](https://github.com/zephyr4123/snug/releases/latest) |

どちらの入手先も同一のパッケージです。Snug は操作対象の Mac 上でのみ動作します。操作する側のデバイス（Android スマートフォン、iPhone、タブレット、パソコン）には UU远程 または CrossDesk だけがあれば十分で、Snug のインストールは不要です。

> 向日葵を使う場合：公式対応版 [Snug for Sunlogin](https://github.com/skyvense/snug-sunlogin) を参照してください。macOS と Windows に対応しています。
>
> Windows ホストの場合：[コミュニティ移植版](#-コミュニティ移植版)を参照してください。

## 🚀 クイックスタート

お使いのリモートアプリの列に沿って設定します。初回の設定後は、普段どおり接続するだけです。

| 手順 | <img src="https://dl.zephyrxiang.com/snug/media/remote-uu.7b92201d.png" width="20" align="absmiddle" alt=""> UU远程 | <img src="https://dl.zephyrxiang.com/snug/media/remote-crossdesk.0ffdb226.png" width="20" align="absmiddle" alt=""> CrossDesk |
| :--- | :--- | :--- |
| 1. アプリ | Mac とスマートフォンに [UU远程](https://uuyc.163.com/) をインストール | Mac とスマートフォンに [CrossDesk](https://github.com/kunkundi/crossdesk) をインストール |
| 2. Snug | Mac に Snug をインストールして開き、ウェルカム画面の案内に従ってアクセシビリティ権限を許可 | 同左 |
| 3. 画面 | 操作不要。接続時に自動で作成 | 設定の「画面」ページで「提前准备虚拟屏」（仮想画面を事前に準備）をオンにすると画面がオンラインになります。続いて Mac の CrossDesk を終了して再度開く |
| 4. スマートフォン | 操作不要 | マウスモードを絶対マウスに設定（既定は相対マウス） |
| 5. 接続 | Mac に接続し、画面リストで「Snug 手机屏」を選択 | Mac に接続し、フローティングメニューのディスプレイ一覧で「Snug 手机屏」を選択 |
| 6. 使用 | スマートフォン画面に App ライブラリが表示され、アプリやウィンドウをタップすると画面いっぱいに表示 | 同左 |

- **タブレット、コンピュータ、横向きのスマートフォン**：先に設定の「画面」ページで画面を追加し、接続後にその画面を選びます
- **CrossDesk を再起動するタイミング**：メニューバーに「重启 CrossDesk 以识别新屏幕」（新しい画面を認識するため CrossDesk を再起動）と表示されたときのみ。画面を追加した後や、Mac の再起動後に CrossDesk が Snug より先に起動したときなど
- 詳しくは[使い方](#-使い方)、CrossDesk の詳細は [CrossDesk の使い方](docs/remotes/crossdesk.md)（中国語）

## ✨ すべてのデバイスでネイティブに

リモートデスクトップアプリはデスクトップ全体を操作側デバイスに合わせて拡大縮小するため、縦横比が異なると黒帯が残り、文字やコントロールが小さくなります。Snug は各デバイスに合った縦横比の画面を追加します。スマートフォンやタブレットではモバイルスケールの全画面ウィンドウとタッチ優先のコントロールを、コンピュータでは黒帯のないそのデバイス本来の解像度を提供します。

### スマートフォン：縦向き・横向き

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/compare-uu-original.cf4158d1.png" width="36%" alt="UU远程 単体：デスクトップ全体がスマートフォンに縮小されている"> <img src="https://dl.zephyrxiang.com/snug/media/phone-claude-code.93e21d9d.png" width="36%" alt="Snug：ウィンドウが画面いっぱいに表示され、文字が大きい"><br><sub>同じ内容 · 左：UU远程 単体 · 右：Snug</sub></p>

- **縦向きと横向き**：機種ごとに比率を計算し、UU远程 のツールバーを避け、2x HiDPI。横向きはコード、ターミナル、横長のページに最適
- **全画面ウィンドウ**：選択したウィンドウが画面全体を占有します
- **大きな文字**：Ghostty、Terminal、iTerm2、VS Code、Cursor、Zed で自動的に適用され、アプリごとに記憶されます

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-landscape-web.a1670af8.png" width="72%" alt="横向きの iPhone：Web ページが全体表示され、右側に UU远程 のツールバーがある"><br><sub>横向き：横長のページを全体表示</sub></p>

### ネイティブなジェスチャー

UU远程 のモバイルクライアントはトラックパッドのジェスチャー規則に従います。スマートフォンとタブレットの画面では、Snug がそれらをタッチスクリーンの規則に再マッピングします。

| タッチ | UU远程 単体 | Snug |
| :--- | :--- | :--- |
| 1 本指のスワイプ | マウスドラッグ。誤ってテキストが選択されやすい | 慣性付きのスクロール |
| 長押ししてからドラッグ | マウスドラッグ | テキスト選択 |
| 長押ししてから離す | 通常のクリック | コンテキストメニュー |

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-demo.2cee4e81.webp" width="30%" alt="ライブデモ：ウィンドウを開き、ポップアップキーボードでコマンドを入力し、セッションを再開し、1 本指でスクロールし、一覧に戻る"> <img src="https://dl.zephyrxiang.com/snug/media/phone-context-menu.997dd70f.png" width="30%" alt="長押しのコンテキストメニュー"><br><sub>1 本指スクロール · 長押しのコンテキストメニュー</sub></p>

- スマートフォンとタブレットの画面に限定され、他のディスプレイや Mac 本体のトラックパッド・マウスには影響しません
- **CrossDesk**：スマートフォン側で絶対マウスモードを選んでください。相対マウスモードでは 1 本指のスワイプはポインタを動かすだけで、Snug は変換しません

### タブレット：全画面・ネイティブなジェスチャー

タブレットから Mac を操作するには、従来は外付けのキーボードとトラックパッドが必要でした。Snug のタブレット画面は機種ごとにディスプレイいっぱいに表示され、タッチにすぐ対応します。

- **横向きと縦向き**：機種ごとに比率を計算し、端から端まで
- **ネイティブなジェスチャー**：スマートフォンと同様。タッチによるスクロール、右クリック、テキスト選択が可能で、外付けトラックパッドは不要
- **快適な文字サイズ**：タブレット本来のサイズよりやや大きく、長時間のセッションに適しています
- **2 カラム**：横向きではアプリとウィンドウを並べて表示。[App ライブラリ](#-app-ライブラリ)を参照

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/ipad-landscape-vscode.7524622f.png" width="56%" alt="横向きの iPad：VS Code が大きな文字で画面いっぱいに表示されている"> <img src="https://dl.zephyrxiang.com/snug/media/ipad-portrait-safari.22fa3ccc.png" width="27%" alt="縦向きの iPad：Safari が画面いっぱいに表示されている"><br><sub>iPad · 横向き · 縦向き</sub></p>

### コンピュータ：全画面・黒帯なし

Snug のコンピュータ画面は操作側コンピュータの解像度で作成され、そのコンピュータがネイティブに表示する内容と一致します。

> コンピュータの黒帯除去は、Snug の前身である [UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（AoyamaShou 作の UU Remote Companion）に由来します。Snug はこれを追加の画面として引き継いでいます。既存のディスプレイはそのまま残り、メインディスプレイは既定では変更されません。

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/macbook-uu-original.4c593493.png" width="46%" alt="MacBook Air 上の UU远程 単体：4K ディスプレイの上下に黒帯があり、文字が小さい"> <img src="https://dl.zephyrxiang.com/snug/media/macbook-snug.32bf15ab.png" width="46%" alt="MacBook Air 上の Snug コンピュータ画面：同じウィンドウが画面いっぱいに表示され、文字がネイティブサイズ"><br><sub>同じウィンドウ · 左：UU远程 単体 · 右：Snug コンピュータ画面</sub></p>

- **ネイティブ解像度**：Mac 全ラインナップの既定解像度と、Windows PC を含む一般的なコンピュータ解像度を内蔵。カスタムサイズにも対応。[カスタム画面](#カスタム画面)を参照
- **ピクセル等倍**：MacBook のノッチ領域は空けたまま、スケーリングなし
- **コンピュータの操作を維持**：ジェスチャーの再マッピングや文字の拡大は行わず、マウスとトラックパッドはそのまま
- **メインディスプレイに設定**（任意、既定ではオフ）：接続のたびにこの画面に直接到達し、メニューバー、Dock、元のメインディスプレイにあったウィンドウもここに表示され、途切れのない継続性を実現します。[メインディスプレイに設定](#メインディスプレイに設定)を参照
- **App ライブラリ**：画面左端の細いタブから開きます。この画面のウィンドウを切り替え、他の画面のウィンドウをこの画面に移動し、ワンクリックで元に戻せます。[App ライブラリ](#-app-ライブラリ)を参照

## 🧩 1 台の Mac を、あらゆるデバイスで

### カスタム画面

デバイス、機種、向き、名前を画面ごとに設定可能。最大 4 画面まで、それぞれ個別にオン・オフできます。

| 設定 | 詳細 |
| :--- | :--- |
| デバイス | スマートフォン、タブレット、コンピュータ。比率と画面上の機能は種類に従います。下の表を参照 |
| 機種 | 機種ライブラリから選択、またはカスタムの解像度・縦横比（例：1080×2400、9×20）。変更は即座に反映され、再接続は不要 |
| 向き | 縦向きまたは横向き。画面を追加するときに選択します |
| 名前 | リモートアプリの画面リストに表示され、識別しやすくなります |

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/settings-add-screen.eed74389.png" width="46%" alt="画面を追加：デバイス、向き、機種、名前"><br><sub>画面を追加：デバイス · 向き · 機種 · 名前</sub></p>

| 画面 | 比率とサイズ | 画面上 |
| :--- | :--- | :--- |
| スマートフォン · 縦向き / 横向き | 機種ごとに計算、UU远程 のツールバーを避ける | App ライブラリ、ホームインジケータ、ネイティブなジェスチャー、大きな文字 |
| タブレット · 横向き / 縦向き | 機種ごとに計算、文字はネイティブよりやや大きい | 上と同様。横向きでは 2 カラム |
| コンピュータ · 横向き | 操作側コンピュータの解像度。MacBook のノッチ領域は空けたまま、ピクセル等倍 | 通常のディスプレイと同様、追加されるものはなし |

- **縦横両対応**：同じスマートフォンやタブレットに縦向き・横向きの画面を 1 つずつ（画面の詳細からもう一方の向きを追加）、向きを変えたらリモートアプリで切り替え
- **複数のスマートフォン**：スマートフォンやタブレットごとに 1 画面、それぞれ独自の機種で
- **デバイスをまたいで**：スマートフォン、タブレット、コンピュータにそれぞれ 1 画面を用意し、使用中のデバイスごとに選択

### 画面リスト

すべての画面は設定の「画面」ページで管理し、使用中の画面はセッション中にリモートアプリの画面リストから選択します。

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/settings-screens-remote.4475b8da.png" width="43%" alt="セッション中の Snug 設定の「画面」ページ：画面リストとメインディスプレイに設定"> <img src="https://dl.zephyrxiang.com/snug/media/uu-screen-list.a161e201.png" width="46%" alt="4 つの Snug 画面を表示する UU远程 の画面メニュー"><br><sub>左：Snug 設定の画面リスト · 右：セッション中の UU远程 の画面リスト</sub></p>

- **必要に応じて**：使わない画面はオフにでき、セッション中に作成されません
- **メインディスプレイに設定**（任意、既定ではオフ）：どの Snug 画面でも利用でき、その画面はその場に留まってすべての接続を受け取ります。[メインディスプレイに設定](#メインディスプレイに設定)を参照
- **ディスプレイのない Mac mini・Mac Studio**：Snug の画面がシステムの既定画面を置き換え、操作側デバイスの解像度で完全なデスクトップを提供します
- **機種ライブラリ**：19 ブランドにわたるスマートフォン 785 機種とタブレット 46 機種（iPhone 8 以降のすべての iPhone、Huawei・Xiaomi・OPPO・vivo・Samsung などの主流 Android 機種、折りたたみ機種の内側・外側画面は別々に掲載）、さらに Mac 13 機種と一般的なコンピュータ解像度 9 種

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-models.391e818d.png" width="36%" alt="機種ページ：現在の機種、カスタム解像度、ブランド別の機種"><br><sub>機種：ブランド別に掲載、カスタム解像度も</sub></p>

### メインディスプレイに設定

任意、既定ではオフ。設定の「画面」ページの下部にあります。選択した画面は Mac のメインディスプレイとしてその場に留まり、UU远程 は接続のたびにその画面に到達し、メニューバー、Dock、元のメインディスプレイにあったウィンドウも一緒に表示されます。

- **留まり続ける理由**：UU远程 は接続が確立された瞬間にメインディスプレイを選び、その後の変更には追従しません。Snug は UU远程 のインターフェースを一切使わず、接続は UU远程 が Mac 上に残すウィンドウとストリームログからしか検知できませんが、その時点では映像はすでにストリーミングされています。そのため選択した画面は接続前に存在し、メインディスプレイになっている必要があり、これがこの条件下で取りうる唯一の方法です
- **トレードオフ**：Dock、新しいウィンドウ、システム警告、ロック画面のログインプロンプトはすべてこの画面に表示され、Mac 本体では見えません。セッション中に Mac がロックされた場合は、操作側デバイスからロックを解除できます。ディスプレイのない Mac や主にリモートで使う Mac を想定しており、有効化の前に確認を求めます
- **オフにする方法**：設定で「不改」（変更しない）に戻す。メニューバーの「取消设为主屏」（メインディスプレイ設定を取消）。またはスマートフォン・タブレット画面の App ライブラリ右上の「取消主屏」（メインを取消）。Mac で再び作業する前にオフにしてください。すでに Mac がロックされている場合は、リモートで接続してこの画面でオフにします
- **セッション終了時**：画面とその上のウィンドウはそのまま残り、次の接続に備えます。設定をオフにするか Snug を終了すると、ウィンドウが戻り、メインディスプレイと配置が復元されます

## 🗂 App ライブラリ

スマートフォンとタブレット画面のホームページ（「App 资源库」）で、モバイルデバイスから Mac のアプリを管理します。検索、起動、切り替え、新規作成、閉じる、終了まで、デスクに戻ることなく行えます。コンピュータ画面では画面左端の細いタブから開きます。

- **実行中**（「运行中」）：実行中のアプリごとに 1 枚のカードを表示し、その下にウィンドウを一覧表示。どのディスプレイや Space にあっても、全画面でも最小化されていても、すべてのウィンドウが含まれます
- **すべて**（「全部」）：Mac 上のすべてのアプリを名前順に並べたグリッド。実行中でないアプリをタップすると起動します
- **検索**：アプリ名とウィンドウタイトルを、中国語、英語、フルピンイン、ピンイン頭文字で検索。「bwl」でメモ（「备忘录」）が見つかります

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-app-library.865fc506.png" width="30%" alt="実行中：ウィンドウがスマートフォン画面にあるアプリが最初に表示される"> <img src="https://dl.zephyrxiang.com/snug/media/phone-all-apps.7d4ada60.png" width="30%" alt="すべて：Mac 上のすべてのアプリのグリッド"> <img src="https://dl.zephyrxiang.com/snug/media/phone-search.d365e194.png" width="30%" alt="検索：bwl でメモが見つかる"><br><sub>実行中 · すべて · ピンイン頭文字検索</sub></p>

- **2 カラム**：横向きのスマートフォンとタブレットでは、左にアプリ、右に選択したアプリのウィンドウ

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-landscape-library.30220d6f.png" width="54%" alt="横向きの iPhone：左にアプリ、右に選択したアプリのウィンドウ"> <img src="https://dl.zephyrxiang.com/snug/media/ipad-landscape-library.b0f8b829.png" width="39%" alt="横向きの iPad：左にアプリ、右に選択したアプリのウィンドウ"><br><sub>2 カラム · 横向きのスマートフォン · タブレット</sub></p>

- **コンピュータ画面**：リモート接続中は画面左端に細いタブが表示され、タップすると App ライブラリが開きます。ウィンドウは場所ごとに「这块屏」（この画面）「其他位置」（他の場所）「没有窗口」（ウィンドウなし）の 3 グループに分かれ、それぞれワンクリックで切り替え、この画面への移動、起動ができます。移動したウィンドウはワンクリックで元に戻せます。リモート側が他の画面を見られない、またはウィンドウを画面間でドラッグできない場合に不可欠です

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/mac-library-panel.686cc617.png" width="38%" alt="コンピュータ画面の App ライブラリ：左端のタブから開き、ウィンドウを場所ごとにグループ化、ワンクリックで切り替え・移動・復元"><br><sub>コンピュータ画面：左端のタブから開く App ライブラリ</sub></p>

| 操作 | 方法 |
| :--- | :--- |
| ウィンドウを開く | ウィンドウをタップして画面いっぱいに表示。アプリをタップすると最近使ったウィンドウを開く |
| 新しいウィンドウ | アプリのカードの「新しいウィンドウ」をタップ。画面の幅で開きます |
| ウィンドウを閉じる | ウィンドウの隣の閉じるボタンをタップし、もう一度タップして確定 |
| アプリを終了 | アプリのカードの「終了」をタップし、もう一度タップして確定。10 秒後に強制終了が可能 |
| 未保存の変更を保存 | 閉じる・終了時の保存プロンプトは現在の画面に表示され、モバイルデバイスから応答できます |
| この画面を抜ける | 右上の「この画面を抜ける」をタップして確定：ウィンドウが戻り、残りのセッションの間この画面は削除され、次のセッションで復元されます（15 秒以内の再接続は同じセッションとみなされます）。CrossDesk のセッション中はウィンドウのみ戻り、画面は残ります。CrossDesk でディスプレイを切り替えてください |
| メインディスプレイを取消 | メインに設定した画面で、右上の「メインを取消」をタップして確定：メインディスプレイが Mac に戻り、この画面はセッション終了時に削除されます |

### iPhone のように動作

| iPhone | Snug のスマートフォン・タブレット画面 |
| :--- | :--- |
| App ライブラリ | ホームページ：Mac のアプリを検索、起動、管理 |
| ホームインジケータ | 下部のインジケータバー。App ライブラリに戻る |
| 左上の「‹ 戻る」 | 左上の「‹ アプリ名」。現在のウィンドウに戻る |

### 任意のアプリで動作

Snug は Mac 自身のウィンドウを表示するため、特定の AI ベンダーに縛られることなく、どんなアプリでも動作します。ターミナルの Claude Code や ChatGPT デスクトップアプリの Codex は、デスクにいるときとまったく同じように動作します。

一部のアプリは、狭い画面では収まらない最小幅を強制します。Snug はまずウィンドウを画面の幅に合わせ、アプリがそれ以上縮小を拒む場合は、ちょうど収まる幅の解像度に画面を切り替え、ウィンドウが再び画面いっぱいになります。

- すべてのウィンドウが全体表示され、途切れることはありません
- 歪みのない比例スケーリング。タップは正確に反映されます
- そうしたウィンドウでは文字がやや小さくなります。モバイルデバイス側でピンチしてズームできます

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-chatgpt.a28ef053.png" width="36%" alt="ChatGPT デスクトップアプリの Codex が Snug のスマートフォン画面いっぱいに表示されている"> <img src="https://dl.zephyrxiang.com/snug/media/phone-fit-settings.4e526ad6.png" width="36%" alt="最小幅を強制するシステム設定が、スマートフォン画面いっぱいに表示されている"><br><sub>左：ChatGPT デスクトップアプリの Codex（ファイルリンクは伏せています） · 右：最小幅があるにもかかわらず画面いっぱいに表示されるシステム設定</sub></p>

## 📸 スクリーンショット

スマートフォンとタブレット画面で利用できます。設定の「触控」（タッチ）ページで「截图」（スクリーンショット）をオンにすると、下部のインジケータバーの左にカメラボタンが表示され、1 タップで全画面ウィンドウを Mac のクリップボードにキャプチャし、任意のアプリに貼り付けられます。キャプチャはウィンドウのネイティブピクセルを使い、リモート圧縮の影響を受けません。

- **トリミング**：キャプチャのたびに左下にサムネイルが表示されます。タップしてトリミングします。既定では全体が選択されており、角や辺をドラッグして範囲を狭め、「完成」（完了）をタップするとクリップボードの画像が置き換わります
- **権限**：別途「画面とシステムオーディオの収録」権限（macOS 14 では画面収録）が必要です。設定の「通用」（一般）ページで「授权…」（許可…）をクリックし、プロンプトが出たら Snug を開き直してください。アクセシビリティ権限とは独立しています
- **既定ではオフ**：オフの間はカメラボタンも収録権限も不要です

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/phone-screenshot-thumbnail.3dfb4e94.png" width="30%" alt="キャプチャ後に左下に表示されるサムネイル"> <img src="https://dl.zephyrxiang.com/snug/media/phone-screenshot-crop.0bd33902.png" width="30%" alt="トリミング：角や辺をドラッグして範囲を狭める"><br><sub>左：キャプチャ後のサムネイル · 右：トリミング</sub></p>

## 🆚 他の方法との比較

| 方法 | 制限 | Snug |
| :--- | :--- | :--- |
| **AI アシスタント内のリモート操作** | ベンダー自身の AI セッションに限定される | 任意のターミナルやアプリ。[任意のアプリで動作](#任意のアプリで動作)を参照 |
| **UU远程 の組み込みターミナル** | ローカルのターミナルとは別物。切断後もプロセスが残り続ける | Mac の既存のターミナルウィンドウ |
| **ディスプレイエミュレータや仮想ディスプレイツール** | 比率が 1 種類のみで、デバイスを切り替えるたびに黒帯が戻る。タッチジェスチャーもウィンドウ管理もない | デバイスごとに専用の画面。スマートフォンとタブレットではネイティブなジェスチャーと App ライブラリ |

- **AI アシスタント内のリモート操作**：例：Claude Remote Control や ChatGPT の Codex。それぞれ単一の製品に縛られています
- **UU远程 の組み込みターミナル**：UU远程 独自の tmux で動作し、Mac 上で進行中の作業（ターミナルの Claude Code など）を再開できません

## 📦 インストール

> **要件**：操作対象の Mac に macOS 14 以降。両方のデバイスで [UU远程](https://uuyc.163.com/) または [CrossDesk](https://github.com/kunkundi/crossdesk) を使用します。向日葵の場合は [Snug for Sunlogin](https://github.com/skyvense/snug-sunlogin) を参照してください。

**ダウンロードしてインストール（推奨）**

1. [ダウンロード](#-ダウンロード)からインストーラを入手します（中国本土では中国ミラーを推奨）
2. Snug を Applications にドラッグして開きます
3. ウェルカムウィンドウの案内に従って、アクセシビリティ権限を付与します（macOS 27 で名称変更）

その後、Snug は追加の設定なしでメニューバーに常駐します。Snug を開き直すと設定が表示されます。

**アップデート**：起動時に確認し、ワンクリックで設定と権限を保持したままインストールできます。手動での確認とアップデート元は設定の「通用」（一般）ページにあります。2.1.0 より前のバージョンは手動での置き換えが必要です。

<div align="center">
<img src="https://dl.zephyrxiang.com/snug/media/welcome.d538a8c3.png" width="30%" alt="ウェルカムウィンドウ：仕組みとアクセシビリティ権限"> <img src="https://dl.zephyrxiang.com/snug/media/settings-screens.694e6c80.png" width="30%" alt="設定の「画面」ページ：画面リストとメインディスプレイに設定"> <img src="https://dl.zephyrxiang.com/snug/media/settings-general.4e8bfc2c.png" width="30%" alt="設定の「一般」ページ：ログイン時に起動、権限、ソフトウェアアップデート">
<p><sub>ウェルカムウィンドウ · 設定：画面 · 設定：一般</sub></p>
</div>

**ソースからビルド**（Xcode と Swift 6 が必要）

```bash
git clone https://github.com/zephyr4123/snug.git
cd snug && scripts/snug install
```

<details>
<summary>UU Remote Companion からの移行</summary>

2 つのアプリは同時に実行すると競合し、Snug は起動時に古いアプリの終了を促します。その watchdog ヘルパーが有効になっていた場合は、次のコマンドも実行してください：

```bash
launchctl bootout gui/$(id -u)/com.corndog.uudisplay.watchdog-agent
rm ~/Library/LaunchAgents/com.corndog.uudisplay.watchdog-agent.plist
```

</details>

## 🧭 使い方

1. **画面を追加**（必要に応じて）：既定では縦向きの画面「Snug 手机屏」（Snug スマートフォン画面）が 1 つ。タブレット、コンピュータ、横向きのスマートフォン画面は、設定の「画面」ページでそれぞれの機種を指定して追加します
2. **画面を切り替え**：接続したら、リモートアプリの画面リストで対応する画面を選びます
3. **アプリまたはウィンドウを選ぶ**：スマートフォンとタブレット画面では、App ライブラリでアプリやウィンドウをタップして画面いっぱいに表示。コンピュータ画面では、左端の細いタブをタップして App ライブラリを開きます
4. **ウィンドウを切り替え**：下部のインジケータバーをタップして App ライブラリに戻ります。別のウィンドウを選ぶと、前のウィンドウは元の場所に戻ります
5. **セッションを終了**：ウィンドウが戻り、文字サイズが復元され、Snug の画面が削除されます。ただしメインディスプレイに設定した画面はそのウィンドウを保持し、事前に準備した画面も残ります

> 💡 UU远程 の画質を最高に設定してください：設定が低いと、特にタブレットで映像がぼやけます。

## 🔒 分離と復元

- **影響は Snug の画面のみ**：ディスプレイをオフにすることも、他のウィンドウに触れることもありません。Snug の画面の外では、リモートアプリは従来どおりに動作します。メインディスプレイが変わるのは「メインディスプレイに設定」がオンのときだけで、設定をオフにするか Snug を終了するまで、選択した画面がメインに保たれます
- **削除前にクリア**：Snug 画面上で直接開いたウィンドウは、画面が削除される前にメインディスプレイへ移動され、隅に押し込まれることはありません
- **まず記録、それから変更**：元のウィンドウ位置と文字サイズを事前に記録しておき、Snug が予期せず終了しても復元できます
- **直接閉じた後も復元**：モバイルデバイス上で直接閉じたウィンドウは、次にそのアプリが Snug 画面のサイズで開くときに、元の場所に戻り、文字サイズも復元されます
- **応答のないアプリはそのまま**：アプリが応答していない間はウィンドウを強制的に移動せず、その理由を画面に表示します
- **データ収集なし**：アップデート確認以外のサーバー接続はなく、データも収集しません。スクリーンショットは Mac のクリップボードにのみ送られ、保存されません

## 🚧 既知の制限

| 制限 | 詳細 |
| :--- | :--- |
| 文書化されていない macOS API に依存 | macOS のメジャーアップデート後に動作しなくなる可能性があります |
| UU远程 は同時に 1 台の操作側デバイスのみ許可 | 画面は順番に使用。複数デバイスからの同時セッションには非対応 |
| UU远程 はすべての接続をメインディスプレイで開始 | 画面リストでの手動選択が 1 回必要。「メインディスプレイに設定」を使うと、すべての接続がその画面に到達します。[メインディスプレイに設定](#メインディスプレイに設定)を参照 |
| Mac 上の UU远程 は最大 5 画面まで表示 | Mac 本体のディスプレイも含まれます。Mac から操作する場合は、先に使わない Snug 画面をオフにしてください |
| CrossDesk は起動時にのみディスプレイを認識 | 「提前准备虚拟屏」（仮想画面を事前に準備）が必要で、画面は常駐します。画面を追加したら CrossDesk を再起動してください。セッション中に画面を抜けるとウィンドウが戻り、画面は残ります |
| 縦横の自動回転はなし | 向きごとに 1 画面を用意し、回転時にリモートアプリで切り替えます |
| 公式製品ではない | UU远程、CrossDesk およびその開発元とは無関係です。これらのアップデートが一部の機能に影響する場合があります |
| セッション後に Snug 画面が残ることがまれにある | システムログがストリームの終了を取りこぼし、メニューバーがセッションを進行中（「远程中」）と表示し続ける場合に発生します。設定で進行中の画面をオフにすると元に戻ります |
| VS Code と Cursor は、ショートカットやメニューでモバイルデバイス上のウィンドウを閉じた後も、拡大された文字サイズを保持することがある | セッション後に文字が大きすぎる場合は、⌘- を押して元に戻してください（必要な回数は閉じるときに画面に表示されます）。ジェスチャーをオンにしてウィンドウ自身の閉じるボタンで閉じた場合や、App ライブラリから閉じた場合は影響しません |
| ディスプレイのない Mac では元の画面に戻らない | macOS はディスプレイが接続されていないときにのみ既定の画面を提供し、Snug 画面が現れるとそれを削除します。App ライブラリの右上から画面を抜けるか、設定でオフにすると、元の画面に戻ります。CrossDesk のセッション中に抜けた場合はウィンドウが戻り、画面は残ります |

各制限の技術的背景：[仕組み](docs/how-it-works.md#已知限制的技术原因)（中国語）

## 🔧 開発

```bash
scripts/snug check     # build and run all tests
scripts/snug install   # build, install, and launch
```

- 3 層構造：`SnugCore`（純粋なロジック）→ `SnugSystem`（システムインターフェース）→ `Snug`（UI）。UU远程 と CrossDesk のアダプターは `Sources/Remotes` にあります
- パッケージング、リリース、起動引数、データの場所：[開発ガイド](docs/development.md)（中国語）
- 接続検知、ウィンドウ配置、ジェスチャー変換：[仕組み](docs/how-it-works.md)（中国語）

**他のリモートアプリへの対応**：アーキテクチャは整備済みです。コアは特定のリモートアプリに依存せず、新たに対応するにはそのアプリ用のアダプターを追加するだけです。対応を追加する PR を歓迎します。フォークして独自に対応することもできます：[リモートアプリの追加](docs/remotes/README.md) · [設計記録](docs/remote-adapter/README.md)（中国語）

## 🧹 アンインストール

1. メニューバーから Snug を終了します（先にウィンドウが復元されます）
2. Snug を Applications からゴミ箱に移動します
3. 任意：`rm -rf ~/Library/Application\ Support/Snug ~/Library/Logs/Snug.log*` で設定とログを削除します
4. 任意：システム設定のアクセシビリティから Snug を削除し、スクリーンショットを使った場合は「画面とシステムオーディオの収録」からも削除します

## 🌐 コミュニティ移植版

移植版は開発元によって 2 種類に分かれます：

- **公式対応版**：リモートデスクトップアプリの開発元が公式に開発し、自社アプリに Snug を対応させたもの
- **個人移植版**：コミュニティの開発者が個人で開発し、Snug を他のプラットフォームへ移植したもの

**公式対応版**

| リモートアプリ | プロジェクト | 開発元 | プラットフォーム | 備考 |
| :--- | :--- | :--- | :--- | :--- |
| 向日葵 | [Snug for Sunlogin](https://github.com/skyvense/snug-sunlogin) | 向日葵公式 | macOS / Windows | Swift / Rust。Snug 2.5.0 がベース。Snug と同じ Mac に共存可能 |

**個人移植版**

| プラットフォーム | プロジェクト | メンテナー | 同期バージョン | 備考 |
| :--- | :--- | :--- | :--- | :--- |
| Windows 10 / 11 | [snug-win](https://github.com/nicocart/snug-win) | [nicocart](https://github.com/nicocart) | Snug 2.8.0 | C# / .NET 10 / WPF。UU远程 と CrossDesk に対応 |
| Windows x64 | [Snug for Windows](https://github.com/rizetngan/snug-for-windows) | [rizetngan](https://github.com/rizetngan) | Snug 2.5.0 | C# / .NET 10 / WPF。安定版リリースあり |
| Windows x64 | [snug-win-rust](https://github.com/mirakyux/snug-win-rust) | [mirakyux](https://github.com/mirakyux) | Snug 2.7.4 | Snug と snug-win をもとに書き直し。Rust / egui。ドライバー同梱の単一 EXE |

各移植版は、それぞれの開発元が独立して開発・リリース・メンテナンスしています。このリポジトリは macOS 版のみを開発・テストしており、これらの移植版はテストしていません。問題は各リポジトリに報告してください。

## ☕ スポンサー

Snug は無料のオープンソースです。お役に立てたなら、コーヒー一杯分のご支援をいただけると、今後の開発と保守の励みになります。

<p align="center"><img src="https://dl.zephyrxiang.com/snug/media/sponsor-wechat.e4a93cbc.jpg" width="30%" alt="WeChat Pay の QR コード"> <img src="https://dl.zephyrxiang.com/snug/media/sponsor-alipay.bd597066.jpg" width="27%" alt="Alipay の QR コード"><br><sub>WeChat Pay · Alipay</sub></p>

## 🙏 謝辞

まず何よりも、**[UU远程](https://uuyc.163.com/)** に心からの敬意を表します。

- **卓越した品質**：安定した接続、応答性の高い操作、自由に調整できる画質とフレームレート。リモート操作は、エンコード、転送、ネットワークをまたぐ接続性など、数多くのエンジニアリング上の課題にわたります。日々の仕事が頼りにできる水準に到達すること自体が、それだけで並外れた技術的成果です
- **3 年間無料**：これほど技術的ハードルの高い製品が、3 年間すべての人に無料で提供され続けたことは、リモートアクセスのエコシステム全体への真の贈り物でした。この開かれた姿勢こそが、コンパニオンアプリや 1 本指スクロールから仮想ディスプレイに至るまで、コミュニティが積み重ねを続けることを可能にしており、Snug もそこから生まれました
- **商業化を支持**：優れた製品は報われるべきです。私たちは UU远程 の有料サービスを全面的に支持しており、作者もすぐに VIP を購読しました

心からの感謝を込めて。

同様に、以下のプロジェクトと貢献者の方々にも感謝します：

- [UUyc-companion](https://github.com/aoyamashou/UUyc-companion)（MIT）：AoyamaShou 作、Snug の前身
- [Better Remote](https://github.com/pincc-debug/better-remote)（MIT）：pincc-debug 作、UU远程 での 1 本指スクロールの手法
- [PermissionFlow](https://github.com/jaywcjlove/PermissionFlow)（MIT）：jaywcjlove（小弟调调）作、権限オンボーディングとドラッグして許可するパネル
- [FreeDisplay](https://github.com/huberdf/FreeDisplay)（MIT）：huberdf 作、`CGVirtualDisplay` インターフェースの宣言
- [CrossDesk](https://github.com/kunkundi/crossdesk)（GPL-3.0）：kunkundi 作、無料・オープンソースのリモートデスクトップアプリ。Snug は公開されている挙動に基づいて連携しており、そのコードは含みません
- [Snug for Sunlogin](https://github.com/skyvense/snug-sunlogin)（MIT）：向日葵公式作、Snug の向日葵対応版（macOS、Windows）
- コミュニティの PR 作者：bubble、gencheng liu、Rongzheng Liu（#10、全画面 Space での UU远程 ウィンドウの読み取り）；yupeng（#26、ディスプレイをまたぐウィンドウをメインディスプレイ経由でルーティング）；李小双（#30、#36、切断直後のセッション終了と、画面削除前および再接続待ち中のポインタの画面外への移動）；LI Long（#31、マルチディスプレイのウィンドウ復元とメニューバー配置の調査）；11ze（#39、バックグラウンドのスキャンとアクセシビリティ読み取りの負荷軽減）；eltociear（#40、日本語版 README）；Nexmoe（#58、CrossDesk の初期アダプター）；rangerTao（#57、UU远程 で画面を切り替えた際の誤った切断判定の特定と修正方針；#61、コンピュータ画面のサイド切り替えの発案と初版）
- 仮想ディスプレイの実装は [DeskPad](https://github.com/Stengo/DeskPad)、[Side Screen](https://github.com/tranvuongquocdat/SideScreen)、Chromium を参考にしています

## ⭐ スター履歴

<p align="center"><a href="https://www.star-history.com/#zephyr4123/snug&Date"><picture><source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=zephyr4123/snug&type=Date&theme=dark"><source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=zephyr4123/snug&type=Date"><img src="https://api.star-history.com/svg?repos=zephyr4123/snug&type=Date" width="80%" alt="Snug の GitHub スターの推移"></picture></a></p>

## 📄 ライセンス

[MIT](LICENSE) © 2026 AoyamaShou, © 2026 zephyr4123
