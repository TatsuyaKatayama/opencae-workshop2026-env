# 第三者ソフトウェア

このリポジトリで独自に作成したコード・設定・文書には Apache-2.0 を適用します。第三者ソフトやコンテナ全体を一律 Apache-2.0 と表記するものではありません。

| 対象 | 取得元・ライセンスの確認先 |
| --- | --- |
| Ubuntu と apt パッケージ | Ubuntu の署名付きアーカイブ。イメージ内 `/usr/share/doc/<package>/copyright` |
| OpenFOAM | https://dl.openfoam.com/repos/deb/ 。GPL-3.0-or-later 等、取得パッケージとソース内の表示を保持 |
| ParaView / 同梱 VTK・依存ソース | https://www.paraview.org/files/v5.13/ParaView-v5.13.3.tar.xz 。各ソース・配布物の License / Copyright と、インストール時のライセンス文書 |
| Mesa / OSMesa / MPI | Ubuntu パッケージごとの copyright |
| ffmpeg | Ubuntu パッケージの copyright と `/opt/workshop-manifest/ffmpeg-buildconf.txt` |
| uv | https://github.com/astral-sh/uv 。MIT / Apache-2.0 等の上流表示 |
| Python パッケージ | PyPI。ロックファイルに版・ハッシュを記録。venv 内 dist-info のライセンスを保持 |

Python パッケージには foamlib、numpy、scipy、matplotlib、japanize-matplotlib、optuna、pandas と推移依存が含まれます。独自作成の cavity ケースは Apache-2.0 で、上流チュートリアルをコピーしたものではありません。イメージに apt 経由で入る OpenFOAM チュートリアルは上流の条件に従います。

取得元と補助配布時の確認事項は [docs/source-distribution.md](docs/source-distribution.md) を参照してください。
