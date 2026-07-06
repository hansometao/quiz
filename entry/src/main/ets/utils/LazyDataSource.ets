/**
 * LazyDataSource.ets
 * 通用懒加载数据源基类
 * 配合 ArkUI 的 LazyForEach 使用，实现大列表虚拟化滚动，避免一次渲染全部节点
 *
 * 使用示例：
 *   const ds = new ArrayDataSource<Question>();
 *   ds.setData(questions);
 *   LazyForEach(ds, (item: Question) => { ... })
 */

/** 数据变更监听器接口（由 ArkUI 框架提供） */
interface DataChangeListener {
  onDataReloaded(): void;
  onDataAdded(index: number): void;
  onDataMoved(from: number, to: number): void;
  onDataDeleted(index: number): void;
  onDataChanged(index: number): void;
}

/** IDataSource 接口（ArkUI LazyForEach 要求实现） */
interface IDataSource {
  totalCount(): number;
  getData(index: number): Object;
  registerDataChangeListener(listener: DataChangeListener): void;
  unregisterDataChangeListener(listener: DataChangeListener): void;
}

/**
 * 通用数组数据源
 * T 为列表项类型
 */
export class ArrayDataSource<T extends Object> implements IDataSource {
  private data: T[] = [];
  private listeners: DataChangeListener[] = [];

  totalCount(): number {
    return this.data.length;
  }

  getData(index: number): T {
    // 越界保护：ArkUI 框架仅以 [0, totalCount) 范围调用，但防御性返回 undefined 避免极端情况下取到 undefined 后下游崩溃
    if (index < 0 || index >= this.data.length) return undefined as T;
    return this.data[index];
  }

  registerDataChangeListener(listener: DataChangeListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  unregisterDataChangeListener(listener: DataChangeListener): void {
    const idx = this.listeners.indexOf(listener);
    if (idx >= 0) {
      this.listeners.splice(idx, 1);
    }
  }

  /** 批量替换全部数据（触发 onDataReloaded） */
  setData(data: T[]): void {
    this.data = [...data];
    this.notifyReloaded();
  }

  /** 追加一条数据 */
  push(item: T): void {
    this.data.push(item);
    this.notifyAdded(this.data.length - 1);
  }

  /** 在指定位置更新一条数据 */
  update(index: number, item: T): void {
    if (index < 0 || index >= this.data.length) return;
    this.data[index] = item;
    this.notifyChanged(index);
  }

  /** 删除指定位置的数据 */
  remove(index: number): void {
    if (index < 0 || index >= this.data.length) return;
    this.data.splice(index, 1);
    this.notifyDeleted(index);
  }

  /** 清空 */
  clear(): void {
    this.data = [];
    this.notifyReloaded();
  }

  /** 获取底层数组的浅拷贝（防止外部直接修改内部数组） */
  getAll(): T[] {
    return [...this.data];
  }

  private notifyReloaded(): void {
    this.safeNotify(l => l.onDataReloaded());
  }
  private notifyAdded(index: number): void {
    this.safeNotify(l => l.onDataAdded(index));
  }
  private notifyDeleted(index: number): void {
    this.safeNotify(l => l.onDataDeleted(index));
  }
  private notifyChanged(index: number): void {
    this.safeNotify(l => l.onDataChanged(index));
  }

  /**
   * 通知监听器：先快照 listeners 数组（通知过程中可能被 unregister），再 try/catch 隔离每个监听器，
   * 单个监听器抛错不会中断其他监听器，也不会影响数据源自身状态
   */
  private safeNotify(fn: (l: DataChangeListener) => void): void {
    const snapshot = [...this.listeners];
    for (const l of snapshot) {
      try {
        fn(l);
      } catch (e) {
        console.error('LazyDataSource listener 通知失败', e);
      }
    }
  }
}
