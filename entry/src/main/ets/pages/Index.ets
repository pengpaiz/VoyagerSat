import { SatelliteListPage } from '../view/pages/SatelliteListPage';
import { PassesPage } from '../view/pages/PassesPage';
import { MapPage } from '../view/pages/MapPage';
import { CalendarPage } from '../view/pages/CalendarPage';
import { SettingsPage } from '../view/pages/SettingsPage';
import { SatelliteApp } from '../common/SatelliteApp';
import { SelectedSats } from '../common/SelectedSats';
import { AppSettings } from '../common/AppSettings';

@Entry
@Component
struct Index {
  @State currentIndex: number = 2;
  private tabsController: TabsController = new TabsController();
  private app: SatelliteApp = SatelliteApp.getInstance();

  aboutToAppear(): void {
    this.app.init(getContext(this));
    SelectedSats.init();
    AppSettings.init();
    // 先加载本地数据，再静默联网更新，避免竞态导致首页空白
    this.app.loadFromDisk().then((): void => {
      this.app.silentStartupUpdate();
    });
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
        MapPage()
      }
      .tabBar(this.tabBar('🗺', '地图', 1))

      TabContent() {
        PassesPage()
      }
      .tabBar(this.tabBar('📡', '过境', 2))

      TabContent() {
        CalendarPage()
      }
      .tabBar(this.tabBar('📅', '日历', 3))

      TabContent() {
        SettingsPage()
      }
      .tabBar(this.tabBar('⚙', '设置', 4))
    }
    .barMode(BarMode.Fixed)
    .barBackgroundColor($r('app.color.color_tab_bar'))
    .onChange((index: number): void => {
      this.currentIndex = index
    })
    .backgroundColor($r('app.color.color_bg'))
  }
}