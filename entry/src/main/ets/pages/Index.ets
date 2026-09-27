import { SatelliteListPage } from '../view/pages/SatelliteListPage';
import { PassesPage } from '../view/pages/PassesPage';
import { SettingsPage } from '../view/pages/SettingsPage';
import { SatelliteApp } from '../common/SatelliteApp';
import { SelectedSats } from '../common/SelectedSats';
import { AppSettings } from '../common/AppSettings';

@Entry
@Component
struct Index {
  @State currentIndex: number = 1;
  private tabsController: TabsController = new TabsController();
  private app: SatelliteApp = SatelliteApp.getInstance();

  aboutToAppear(): void {
    this.app.init(getContext(this));
    SelectedSats.init();
    AppSettings.init();
    this.app.loadFromDisk();
    // 启动时静默更新数据与定位
    this.app.silentStartupUpdate();
  }

  @Builder
  tabBar(icon: ResourceStr, label: string, index: number) {
    Column({ space: 4 }) {
      Text(icon)
        .fontSize(22)
        .fontColor(this.currentIndex === index ? $r('app.color.color_primary') : $r('app.color.color_text_secondary'))
      Text(label)
        .fontSize(12)
        .fontColor(this.currentIndex === index ? $r('app.color.color_primary') : $r('app.color.color_text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  build() {
    Tabs({ barPosition: BarPosition.End, index: this.currentIndex, controller: this.tabsController }) {
      TabContent() {
        SatelliteListPage()
      }
      .tabBar(this.tabBar('🛰', '卫星', 0))

      TabContent() {
        PassesPage()
      }
      .tabBar(this.tabBar('📡', '过境', 1))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.tabBar('⚙', '设置', 2))
    }
    .barMode(BarMode.Fixed)
    .onChange((index: number): void => {
      this.currentIndex = index
    })
    .backgroundColor($r('app.color.color_bg'))
  }
}