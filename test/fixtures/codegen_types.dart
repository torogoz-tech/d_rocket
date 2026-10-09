import 'package:d_rocket/d_rocket.dart';

part 'codegen_types.d_rocket_orm.g.dart';
part 'codegen_types.d_rocket_serializer.g.dart';

@Serializable()
@Table()
class CodegenTypesEntity {
  CodegenTypesEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.timestamp,
    required this.optionalTimestamp,
    required this.amount,
  });

  @PrimaryKey()
  final String id;

  @Column()
  final String name;

  @Column()
  final String? description;

  @Column()
  final DateTime timestamp;

  @Column()
  final DateTime? optionalTimestamp;

  @Column()
  final double? amount;
}
