# Order By 执行原理

## 全字段排序与 RowID 排序



### 全字段排序

针对某一列进行排序操作的时候，有一些操作是在内存中完成，还有一些操作会在外部排序完成，主要是取决于 sort_buffer_size （MySQL 为排序开辟的内存的大小）：

- 排序数据量小于 sort_buffer_size 在内存中进行排序操作；
- 大于 sort_buffer_size 的话则使用磁盘的临时文件辅助排序。



> 使用磁盘临时文件排序的时候有一个参数：number_of_tmp_files
>
> 这个参数是在排序的时候 MySQL 会使用这个参数将数据块在这个参数大小的文件中进行排序，类似我们了解到的归并排序，之后进行合并到一个大的文件进行排序。





### RowID 排序

在操作中，有一个对行长度大小控制的参数 max_length_for_sort_data ，当 MySQL 操作时发现单行长度操作这个参数设置的值，此时需要更换算法处理排序，也就是 RowID 排序：



> 前提：对 name 字段进行排序操作：

1. 初始化sort_buffer，确定放入两个字段，即name和id；
2. 从索引city找到第一个满足city='杭州’条件的主键id，也就是图中的ID_X；
3. 到主键id索引取出整行，取name、id这两个字段，存入sort_buffer中；
4. 从索引city取下一个记录的主键id；
5. 重复步骤3、4直到不满足city='杭州’条件为止，也就是图中的ID_Y；
6. 对sort_buffer中的数据按照字段name进行排序；
7. 遍历排序结果，取前1000行，并按照id的值回到原表中取出city、name和age三个字段返回给客户端。



**MySQL 设计思想：如果内存足够、多利用内存，尽量减少对磁盘的访问。**













































